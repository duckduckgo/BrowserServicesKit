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
import Common

public protocol PhishingDetectionDataProviding {
    var embeddedRevision: Int { get }
    func loadEmbeddedFilterSet() -> Set<Filter>
    func loadEmbeddedHashPrefixes() -> Set<String>
}

public class PhishingDetectionDataProvider: PhishingDetectionDataProviding {
    public private(set) var embeddedRevision: Int
    var embeddedFilterSetURL: URL
    var embeddedFilterSetDataSHA: String
    var embeddedHashPrefixURL: URL
    var embeddedHashPrefixDataSHA: String

    public init(revision: Int, filterSetURL: URL, filterSetDataSHA: String, hashPrefixURL: URL, hashPrefixDataSHA: String) {
        embeddedFilterSetURL = filterSetURL
        embeddedFilterSetDataSHA = filterSetDataSHA
        embeddedHashPrefixURL = hashPrefixURL
        embeddedHashPrefixDataSHA = hashPrefixDataSHA
        embeddedRevision = revision
    }

    public func loadEmbeddedFilterSet() -> Set<Filter> {
        do {
            let filterSetData = try Data(contentsOf: embeddedFilterSetURL)
            let sha256 = SHA256.hash(data: filterSetData)
            let hashString = sha256.compactMap { String(format: "%02x", $0) }.joined()

            guard hashString == embeddedFilterSetDataSHA else {
                os_log(.debug, log: .phishingDetection, "\(self): 🔴 Fatal Error: SHA mismatch for filterSet JSON file. Expected \(embeddedFilterSetDataSHA), got \(hashString)")
//                assertionFailure("SHA mismatch for filterSet JSON file. Expected \(embeddedFilterSetDataSHA), got \(hashString)")
                return Set()
            }

            let filterSet = try JSONDecoder().decode(Set<Filter>.self, from: filterSetData)

            return filterSet
        } catch {
            fatalError("Error loading filterSet data: \(error)")
        }
    }

    public func loadEmbeddedHashPrefixes() -> Set<String> {
        do {
            let hashPrefixData = try Data(contentsOf: embeddedHashPrefixURL)
            let sha256 = SHA256.hash(data: hashPrefixData)
            let hashString = sha256.compactMap { String(format: "%02x", $0) }.joined()

            guard hashString == embeddedHashPrefixDataSHA else {
                os_log(.debug, log: .phishingDetection, "\(self): 🔴 Fatal Error: SHA mismatch for hashPrefixes JSON file. Expected \(embeddedHashPrefixDataSHA) got \(hashString)")
//                assertionFailure("SHA mismatch for hashPrefixes JSON file. Expected \(embeddedHashPrefixDataSHA) got \(hashString)")
                return Set()
            }

            let hashPrefixes = try JSONDecoder().decode(Set<String>.self, from: hashPrefixData)
            return hashPrefixes
        } catch {
            fatalError("Error loading hashPrefixes data: \(error)")
        }
    }
}
