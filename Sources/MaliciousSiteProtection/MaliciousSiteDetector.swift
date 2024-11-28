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
    /// Evaluates the given URL to determine its threat level.
    /// - Parameter url: The URL to evaluate.
    /// - Returns: An optional ThreatKind indicating the type of threat, or nil if no threat is detected.
    func evaluate(_ url: URL) async -> ThreatKind?
}

/// Class responsible for detecting malicious sites by evaluating URLs against local filters and an external API.
/// entry point: `func evaluate(_: URL) async -> ThreatKind?`
public final class MaliciousSiteDetector: MaliciousSiteDetecting {
    // Type aliases for easier symbol navigation in Xcode.
    typealias PhishingDetector = MaliciousSiteDetector
    typealias MalwareDetector = MaliciousSiteDetector

    private enum Constants {
        static let hashPrefixStoreLength: Int = 8
        static let hashPrefixParamLength: Int = 4
    }

    private let apiClient: APIClientProtocol
    private let dataManager: DataManaging
    private let eventMapping: EventMapping<Event>

    public init(apiClient: APIClientProtocol = APIClient(), dataManager: DataManaging, eventMapping: EventMapping<Event>) {
        self.apiClient = apiClient
        self.dataManager = dataManager
        self.eventMapping = eventMapping
    }

    private func checkLocalFilters(hostHash: String, canonicalUrl: URL, for threatKind: ThreatKind) async -> Bool {
        let filterSet = await dataManager.dataSet(for: .filterSet(threatKind: threatKind))
        let matchesLocalFilters = filterSet[hostHash]?.contains(where: { regex in
            canonicalUrl.absoluteString.matches(pattern: regex)
        }) ?? false

        return matchesLocalFilters
    }

    private func checkApiMatches(hostHash: String, canonicalUrl: URL) async -> Match? {
        let hashPrefixParam = String(hostHash.prefix(Constants.hashPrefixParamLength))
        let matches: [Match]
        do {
            matches = try await apiClient.matches(forHashPrefix: hashPrefixParam).matches
        } catch {
            Logger.general.error("Error fetching matches from API: \(error)")
            return nil
        }

        if let match = matches.first(where: { match in
            match.hash == hostHash && canonicalUrl.absoluteString.matches(pattern: match.regex)
        }) {
            return match
        }
        return nil
    }

    /// Evaluates the given URL to determine its threat level.
    public func evaluate(_ url: URL) async -> ThreatKind? {
        guard let canonicalHost = url.canonicalHost(),
              let canonicalUrl = url.canonicalURL() else { return .none }

        let hostHash = canonicalHost.sha256
        let hashPrefix = String(hostHash.prefix(Constants.hashPrefixStoreLength))

        for threatKind in ThreatKind.allCases /* phishing, malware.. */ {
            let hashPrefixes = await dataManager.dataSet(for: .hashPrefixes(threatKind: threatKind))
            guard hashPrefixes.contains(hashPrefix) else { continue }

            // Check local filterSet first
            if await checkLocalFilters(hostHash: hostHash, canonicalUrl: canonicalUrl, for: threatKind) {
                eventMapping.fire(.errorPageShown(clientSideHit: true))
                return threatKind
            }

            // If nothing found, hit the API to get matches
            let match = await checkApiMatches(hostHash: hostHash, canonicalUrl: canonicalUrl)
            if let match {
                eventMapping.fire(.errorPageShown(clientSideHit: false))
                return match.category.map(ThreatKind.init) ?? threatKind
            }

            // the API detects both phishing and malware so if it didn‘t find any matches it‘s safe to return early.
            return nil
        }

        return .none
    }

}
