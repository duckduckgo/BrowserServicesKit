//
//  PhishingDetector.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import CryptoKit
import Common
import WebKit

public enum PhishingDetectionError: CustomNSError {
    case detected

    public static let errorDomain: String = "PhishingDetectionError"

    public var errorCode: Int {
        switch self {
        case .detected:
            return 1331
        }
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .detected:
            return [NSLocalizedDescriptionKey: "Phishing detected"]
        }
    }

    public var rawValue: Int {
        return self.errorCode
    }
}

public protocol PhishingDetecting {
	func isMalicious(url: URL) async -> Bool
}

public class PhishingDetector: PhishingDetecting {
    let hashPrefixStoreLength: Int = 8
    let hashPrefixParamLength: Int = 4
	let apiClient: PhishingDetectionClientProtocol
	let dataStore: PhishingDetectionDataSaving
    let eventMapping: EventMapping<PhishingDetectionEvents>

    public init(apiClient: PhishingDetectionClientProtocol, dataStore: PhishingDetectionDataSaving, eventMapping: EventMapping<PhishingDetectionEvents>) {
		self.apiClient = apiClient
		self.dataStore = dataStore
        self.eventMapping = eventMapping
	}

	private func getMatches(hashPrefix: String) async -> Set<Match> {
		return Set(await apiClient.getMatches(hashPrefix: hashPrefix))
	}

	private func inFilterSet(hash: String) -> Set<Filter> {
		return Set(dataStore.filterSet.filter { $0.hashValue == hash })
	}

	private func matchesUrl(hash: String, regexPattern: String, url: URL, hostnameHash: String) -> Bool {
		if hash == hostnameHash,
		   let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
			let urlString = url.absoluteString
			let range = NSRange(location: 0, length: urlString.utf16.count)
			return regex.firstMatch(in: urlString, options: [], range: range) != nil
		}
		return false
	}

    private func generateHashPrefix(for canonicalHost: String, length: Int) -> String {
        let hostnameHash = SHA256.hash(data: Data(canonicalHost.utf8)).map { String(format: "%02hhx", $0) }.joined()
        return String(hostnameHash.prefix(length))
    }

    private func fetchMatches(hashPrefix: String) async -> [Match] {
        return await apiClient.getMatches(hashPrefix: hashPrefix)
    }

    private func checkLocalFilters(canonicalHost: String, canonicalUrl: URL) -> Bool {
        let hostnameHash = generateHashPrefix(for: canonicalHost, length: Int.max)
        let filterHit = inFilterSet(hash: hostnameHash)
        for filter in filterHit where matchesUrl(hash: filter.hashValue, regexPattern: filter.regex, url: canonicalUrl, hostnameHash: hostnameHash) {
            eventMapping.fire(PhishingDetectionEvents.errorPageShown(clientSideHit: true))
            return true
        }
        return false
    }

    private func checkApiMatches(canonicalHost: String, canonicalUrl: URL) async -> Bool {
        let hashPrefixParam = generateHashPrefix(for: canonicalHost, length: hashPrefixParamLength)
        let matches = await fetchMatches(hashPrefix: hashPrefixParam)
        let hostnameHash = generateHashPrefix(for: canonicalHost, length: Int.max)
        for match in matches where matchesUrl(hash: match.hash, regexPattern: match.regex, url: canonicalUrl, hostnameHash: hostnameHash) {
            eventMapping.fire(PhishingDetectionEvents.errorPageShown(clientSideHit: false))
            return true
        }
        return false
    }

    public func isMalicious(url: URL) async -> Bool {
        guard let canonicalHost = url.canonicalHost(), let canonicalUrl = url.canonicalURL() else { return false }

        let hashPrefix = generateHashPrefix(for: canonicalHost, length: hashPrefixStoreLength)
        if dataStore.hashPrefixes.contains(hashPrefix) {
            // Check local filterSet first
            if checkLocalFilters(canonicalHost: canonicalHost, canonicalUrl: canonicalUrl) {
                return true
            }
            // If nothing found, hit the API to get matches
            if await checkApiMatches(canonicalHost: canonicalHost, canonicalUrl: canonicalUrl) {
                return true
            }
        }

        return false
    }
}
