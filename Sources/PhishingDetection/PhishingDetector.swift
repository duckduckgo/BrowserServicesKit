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
            return 1
        }
    }

    public var errorUserInfo: [String : Any] {
        switch self {
        case .detected:
            return [NSLocalizedDescriptionKey: "Phishing detected"]
        }
    }
    
    public var rawValue: Int {
        return self.errorCode
    }
}


public struct Filter: Decodable, Encodable, Hashable {
	public var hashValue: String
	public var regex: String

	enum CodingKeys: String, CodingKey {
		case hashValue = "hash"
		case regex
	}

	public init(hashValue: String, regex: String) {
		self.hashValue = hashValue
		self.regex = regex
	}
}

public struct Match: Decodable, Encodable, Hashable {
	var hostname: String
	var url: String
	var regex: String
	var hash: String

	public init(hostname: String, url: String, regex: String, hash: String) {
		self.hostname = hostname
		self.url = url
		self.regex = regex
		self.hash = hash
	}
}

public protocol PhishingDetecting {
	func isMalicious(url: URL) async -> Bool
}

public class PhishingDetector: PhishingDetecting {
	var apiClient: PhishingDetectionClientProtocol
	var dataStore: PhishingDetectionDataStoring

	public init(apiClient: PhishingDetectionClientProtocol, dataProvider: PhishingDetectionDataProviding, dataStore: PhishingDetectionDataStoring) {
		self.apiClient = apiClient
		self.dataStore = dataStore
	}

	func getMatches(hashPrefix: String) async -> Set<Match> {
		return Set(await apiClient.getMatches(hashPrefix: hashPrefix))
	}

	func inFilterSet(hash: String) -> Set<Filter> {
		return Set(dataStore.filterSet.filter { $0.hashValue == hash })
	}

	func matchesUrl(hash: String, regexPattern: String, url: URL, hostnameHash: String) -> Bool {
		if hash == hostnameHash,
		   let regex = try? NSRegularExpression(pattern: regexPattern, options: [])
		{
			let urlString = url.absoluteString
			let range = NSRange(location: 0, length: urlString.utf16.count)
			return regex.firstMatch(in: urlString, options: [], range: range) != nil
		}
		return false
	}

	public func isMalicious(url: URL) async -> Bool {
		guard let canonicalHost = url.canonicalHost() else { return false }
		let hostnameHash = SHA256.hash(data: Data(canonicalHost.utf8)).map { String(format: "%02hhx", $0) }.joined()
		let hashPrefix = String(hostnameHash.prefix(8))
		if dataStore.hashPrefixes.contains(hashPrefix) {
			// Check local filterSet first
			let filterHit = inFilterSet(hash: hostnameHash)
            for filter in filterHit where matchesUrl(hash: filter.hashValue, regexPattern: filter.regex, url: url, hostnameHash: hostnameHash) {
                return true
            }
			// If nothing found, hit the API to get matches
			let matches = await apiClient.getMatches(hashPrefix: hashPrefix)
			for match in matches where matchesUrl(hash: match.hash, regexPattern: match.regex, url: url, hostnameHash: hostnameHash) {
				return true
			}
		}
		return false
	}
}
