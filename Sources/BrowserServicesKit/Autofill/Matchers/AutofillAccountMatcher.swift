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

public protocol AutofillAccountMatcher {
    func findMatches(accounts: [SecureVaultModels.WebsiteAccount], for url: String) -> [SecureVaultModels.WebsiteAccount]
}

public struct AutofillWebsiteAccountMatcher: AutofillAccountMatcher {

    private let autofillUrlMatcher: AutofillDomainNameUrlMatcher
    private let tld: TLD

    public init(autofillUrlMatcher: AutofillDomainNameUrlMatcher, tld: TLD) {
        self.autofillUrlMatcher = autofillUrlMatcher
        self.tld = tld
    }

    public func findMatches(accounts: [SecureVaultModels.WebsiteAccount], for url: String) -> [SecureVaultModels.WebsiteAccount] {
        return accounts.dedupedAndSortedForDomain(url, tld: tld)
    }
    
}
