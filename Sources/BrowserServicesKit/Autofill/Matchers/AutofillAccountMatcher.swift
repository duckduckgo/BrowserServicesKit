//
//  AutofillAccountMatcher.swift
//  DuckDuckGo
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
import Common

public struct AccountMatches {
    public let perfectMatches: [SecureVaultModels.WebsiteAccount]
    public let partialMatches: [String: [SecureVaultModels.WebsiteAccount]]

    public init(perfectMatches: [SecureVaultModels.WebsiteAccount],
                partialMatches: [String: [SecureVaultModels.WebsiteAccount]]) {
        self.perfectMatches = perfectMatches
        self.partialMatches = partialMatches
    }
}

public protocol AutofillAccountMatcher {
    func findMatchesSortedByLastUpdated(accounts: [SecureVaultModels.WebsiteAccount], for url: String) -> AccountMatches
}

public struct AutofillWebsiteAccountMatcher: AutofillAccountMatcher {

    private let autofillUrlMatcher: AutofillDomainNameUrlMatcher
    private let tld: TLD

    public init(autofillUrlMatcher: AutofillDomainNameUrlMatcher, tld: TLD) {
        self.autofillUrlMatcher = autofillUrlMatcher
        self.tld = tld
    }

    public func findMatchesSortedByLastUpdated(accounts: [SecureVaultModels.WebsiteAccount], for url: String) -> AccountMatches {
        let matches = buildMatches(accounts: accounts, for: url)
        return sort(matches: matches)
    }

    /// Builds a list of accounts that are perfect matches for the given url
    /// and a dictionary of groups of accounts with the same subdomain that are partial matches for the given url.
    private func buildMatches(accounts: [SecureVaultModels.WebsiteAccount], for url: String) -> AccountMatches {
        var perfectMatches = [SecureVaultModels.WebsiteAccount]()
        var partialMatches = [String: [SecureVaultModels.WebsiteAccount]]()
        let currentUrlComponents = autofillUrlMatcher.normalizeSchemeForAutofill(url)

        for account in accounts {
            if let savedUrlComponents = autofillUrlMatcher.normalizeSchemeForAutofill(account.domain) {
                if !autofillUrlMatcher.isMatchingForAutofill(currentSite: url, savedSite: account.domain, tld: tld) {
                    continue
                }

                if currentUrlComponents?.subdomain(tld: tld) == savedUrlComponents.subdomain(tld: tld) {
                    perfectMatches.append(account)
                } else {
                    partialMatches[account.domain, default: []].append(account)
                }
            }
        }

        return AccountMatches(perfectMatches: perfectMatches, partialMatches: partialMatches)
    }

    private func sort(matches: AccountMatches) -> AccountMatches {
        let sortedPerfectMatches = matches.perfectMatches.sorted { $0.lastUpdated > $1.lastUpdated }
        let partialMatches = matches.partialMatches.mapValues { $0.sorted { $0.lastUpdated > $1.lastUpdated } }
        return AccountMatches(perfectMatches: sortedPerfectMatches, partialMatches: partialMatches)
    }

}