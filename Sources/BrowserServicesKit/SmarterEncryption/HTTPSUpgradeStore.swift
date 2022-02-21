//
//  HTTPSUpgradeStore.swift
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

import BloomFilterWrapper

public protocol HTTPSUpgradeStore {
    
    // MARK: - Bloom filter
    
    var bloomFilter: BloomFilterWrapper? { get }
    var bloomFilterSpecification: HTTPSBloomFilterSpecification? { get }
    @discardableResult func persistBloomFilter(specification: HTTPSBloomFilterSpecification, data: Data) -> Bool
    
    // MARK: - Excluded domains
    
    func hasExcludedDomain(_ domain: String) -> Bool
    @discardableResult func persistExcludedDomains(_ domains: [String]) -> Bool
    
}
