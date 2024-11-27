//
//  FilterDictionary.swift
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

public struct FilterDictionary: Codable, Equatable {

    /// Filter set revision
    public var revision: Int

    /// [Hash: [RegEx]] mapping
    ///
    /// - **Key**: SHA256 hash sum of a canonical host name
    /// - **Value**: An array of regex patterns used to match whole URLs
    ///
    /// ```
    /// {
    ///     "3aeb002460381c6f258e8395d3026f571f0d9a76488dcd837639b13aed316560" : [
    ///         "(?i)^https?\\:\\/\\/[\\w\\-\\.]+(?:\\:(?:80|443))?[\\/\\\\]+BETS1O\\-GIRIS[\\/\\\\]+BETS1O(?:[\\/\\\\]+|\\?|$)"
    ///     ],
    ///     ...
    /// }
    /// ```
    public var filters: [String: Set<String>]

    public init(revision: Int, filters: [String: Set<String>]) {
        self.filters = filters
        self.revision = revision
    }

    /// Subscript to access regex patterns by SHA256 host name hash
    subscript(hash: String) -> Set<String>? {
        filters[hash]
    }

    public mutating func subtract<Seq: Sequence>(_ itemsToDelete: Seq) where Seq.Element == Filter {
        for filter in itemsToDelete {
            withUnsafeMutablePointer(to: &filters[filter.hash]) { item in
                item.pointee?.remove(filter.regex)
                if item.pointee?.isEmpty == true {
                    item.pointee = nil
                }
            }
        }
    }

    public mutating func formUnion<Seq: Sequence>(_ itemsToAdd: Seq) where Seq.Element == Filter {
        for filter in itemsToAdd {
            filters[filter.hash, default: []].insert(filter.regex)
        }
    }

}
