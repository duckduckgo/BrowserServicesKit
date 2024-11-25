//
//  MaliciousSiteDetector.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import CryptoKit
import Foundation

public protocol MaliciousSiteDetecting {
    func evaluate(_ url: URL) async -> ThreatKind?
}

public final class MaliciousSiteDetector: MaliciousSiteDetecting {
    // for easier Xcode symbol navigation
    typealias PhishingDetector = MaliciousSiteDetector
    typealias MalwareDetector = MaliciousSiteDetector

    let hashPrefixStoreLength: Int = 8
    let hashPrefixParamLength: Int = 4
    let apiClient: APIClientProtocol
    let dataManager: DataManaging
    let eventMapping: EventMapping<Event>

    public init(apiClient: APIClientProtocol = APIClient(), dataManager: DataManaging, eventMapping: EventMapping<Event>) {
        self.apiClient = apiClient
        self.dataManager = dataManager
        self.eventMapping = eventMapping
    }

    private func inFilterSet(hash: String) -> Set<Filter> {
        return Set(dataManager.filterSet.filter { $0.hash == hash })
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
        do {
            let response = try await apiClient.matches(forHashPrefix: hashPrefix)
            return response.matches
        } catch {
            Logger.api.error("Failed to fetch matches for hash prefix: \(hashPrefix): \(error.localizedDescription)")
            return []
        }
    }

    private func checkLocalFilters(canonicalHost: String, canonicalUrl: URL) -> Bool {
        let hostnameHash = generateHashPrefix(for: canonicalHost, length: Int.max)
        let filterHit = inFilterSet(hash: hostnameHash)
        for filter in filterHit where matchesUrl(hash: filter.hash, regexPattern: filter.regex, url: canonicalUrl, hostnameHash: hostnameHash) {
            eventMapping.fire(.errorPageShown(clientSideHit: true))
            return true
        }
        return false
    }

    private func checkApiMatches(canonicalHost: String, canonicalUrl: URL) async -> Bool {
        let hashPrefixParam = generateHashPrefix(for: canonicalHost, length: hashPrefixParamLength)
        let matches = await fetchMatches(hashPrefix: hashPrefixParam)
        let hostnameHash = generateHashPrefix(for: canonicalHost, length: Int.max)
        for match in matches where matchesUrl(hash: match.hash, regexPattern: match.regex, url: canonicalUrl, hostnameHash: hostnameHash) {
            eventMapping.fire(.errorPageShown(clientSideHit: false))
            return true
        }
        return false
    }

    public func evaluate(_ url: URL) async -> ThreatKind? {
        guard let canonicalHost = url.canonicalHost(), let canonicalUrl = url.canonicalURL() else { return .none }

        for threatKind in ThreatKind.allCases {
            let hashPrefix = generateHashPrefix(for: canonicalHost, length: hashPrefixStoreLength)
            if dataManager.hashPrefixes.contains(hashPrefix) {
                // Check local filterSet first
                if checkLocalFilters(canonicalHost: canonicalHost, canonicalUrl: canonicalUrl) {
                    return threatKind
                }
                // If nothing found, hit the API to get matches
                if await checkApiMatches(canonicalHost: canonicalHost, canonicalUrl: canonicalUrl) {
                    return threatKind
                }
            }
        }

        return .none
    }
}
