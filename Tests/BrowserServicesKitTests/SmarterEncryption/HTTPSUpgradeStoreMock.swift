//
//  HTTPSUpgradeStoreMock.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
@testable import BrowserServicesKit
@testable import BloomFilterWrapper

struct HTTPSUpgradeStoreMock: HTTPSUpgradeStore {

    var bloomFilter: BloomFilterWrapper?
    var bloomFilterSpecification: HTTPSBloomFilterSpecification?
    func loadBloomFilter() -> BloomFilter? {
        guard let bloomFilter, let bloomFilterSpecification else { return nil }
        return .init(wrapper: bloomFilter, specification: bloomFilterSpecification)
    }

    var excludedDomains: [String]
    func hasExcludedDomain(_ domain: String) -> Bool {
        excludedDomains.contains(domain)
    }

    func persistBloomFilter(specification: BrowserServicesKit.HTTPSBloomFilterSpecification, data: Data) throws {
        fatalError()
    }

    func persistExcludedDomains(_ domains: [String]) throws {
        fatalError()
    }

}
