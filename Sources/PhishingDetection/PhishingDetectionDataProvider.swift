//
//  PhishingDetectionDataProvider.swift
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

import Foundation
import CryptoKit

public protocol PhishingDetectionDataProviderProtocol {
    var embeddedFilterSet: Set<Filter> { get }
    var embeddedHashPrefixes: Set<String> { get }
}

public class PhishingDetectionDataProvider: PhishingDetectionDataProviderProtocol {
    public struct Constants {
        public static let hashPrefixDataSHA = "21b047a9950fcaf86034a6b16181e18815cb8d276386d85c8977ca8c5f8aa05f"
        public static let filterSetDataSHA = "4fd2868a4f264501ec175ab866504a2a96c8d21a3b5195b405a4a83b51eae504"
        public static let revision = 2
    }
    
    public var embeddedFilterSet: Set<Filter> {
        return Self.loadFilterSet()
    }
    
    public var embeddedHashPrefixes: Set<String> {
        return Self.loadHashPrefixes()
    }
    
    static var embeddedRevision: Int {
        return Self.Constants.revision
    }
    
    static var hashPrefixURL: URL {
        return Bundle.module.url(forResource: "hashPrefixes", withExtension: "json")!
    }
    
    static var filterSetURL: URL {
        return Bundle.module.url(forResource: "filterSet", withExtension: "json")!
    }

    public static func loadFilterSet() -> Set<Filter> {
        do {
            let filterSetData = try Data(contentsOf: filterSetURL)
            let sha256 = SHA256.hash(data: filterSetData)
            let hashString = sha256.compactMap { String(format: "%02x", $0) }.joined()
            
            guard hashString == PhishingDetectionDataProvider.Constants.filterSetDataSHA else {
                fatalError("SHA mismatch for filterSet JSON file. Expected \(PhishingDetectionDataProvider.Constants.filterSetDataSHA), got \(hashString)")
            }

            let filterSet = try JSONDecoder().decode(Set<Filter>.self, from: filterSetData)

            return filterSet
        } catch {
            fatalError("Error loading filterSet data: \(error)")
        }
    }

    public static func loadHashPrefixes() -> Set<String> {
        do {
            let hashPrefixData = try Data(contentsOf: hashPrefixURL)
            let sha256 = SHA256.hash(data: hashPrefixData)
            let hashString = sha256.compactMap { String(format: "%02x", $0) }.joined()
            
            guard hashString == PhishingDetectionDataProvider.Constants.hashPrefixDataSHA else {
                fatalError("SHA mismatch for hashPrefixes JSON file. Expected \(PhishingDetectionDataProvider.Constants.hashPrefixDataSHA) got \(hashString)")
            }

            let hashPrefixes = try JSONDecoder().decode(Set<String>.self, from: hashPrefixData)

            return hashPrefixes
        } catch {
            fatalError("Error loading hashPrefixes data: \(error)")
        }
    }
}
