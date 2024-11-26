//
//  IncrementallyUpdatableMaliciousSiteDataSet.swift
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

public protocol IncrementallyUpdatableMaliciousSiteDataSet: Codable, Equatable {
    /// Set Element Type (Hash Prefix or Filter)
    associatedtype Element: Codable, Hashable
    associatedtype APIRequestType: MaliciousSiteDataChangeSetAPIRequestProtocol, APIRequestProtocol where APIRequestType.ResponseType == APIClient.ChangeSetResponse<Element>

    var revision: Int { get set }

    init(revision: Int, items: some Sequence<Element>)

    mutating func subtract<Seq: Sequence>(_ itemsToDelete: Seq) where Seq.Element == Element
    mutating func formUnion<Seq: Sequence>(_ itemsToAdd: Seq) where Seq.Element == Element

    /// Apply ChangeSet from local data revision to actual revision loaded from API
    mutating func apply(_ changeSet: APIClient.ChangeSetResponse<Element>)
}

extension IncrementallyUpdatableMaliciousSiteDataSet {
    public mutating func apply(_ changeSet: APIClient.ChangeSetResponse<Element>) {
        if changeSet.replace {
            self = .init(revision: changeSet.revision, items: changeSet.insert)
        } else {
            self.subtract(changeSet.delete)
            self.formUnion(changeSet.insert)
            self.revision = changeSet.revision
        }
    }
}

extension HashPrefixSet: IncrementallyUpdatableMaliciousSiteDataSet {
    public typealias Element = String
    public typealias APIRequestType = APIClient.Request.HashPrefixes

    public static func apiRequest(for threatKind: ThreatKind, revision: Int) -> APIRequestType {
        .hashPrefixes(threatKind: threatKind, revision: revision)
    }
}

extension FilterDictionary: IncrementallyUpdatableMaliciousSiteDataSet {
    public typealias Element = Filter
    public typealias APIRequestType = APIClient.Request.FilterSet

    public init(revision: Int, items: some Sequence<Filter>) {
        let filtersDictionary = items.reduce(into: [String: Set<String>]()) { result, filter in
            result[filter.hash, default: []].insert(filter.regex)
        }
        self.init(revision: revision, filters: filtersDictionary)
    }

    public static func apiRequest(for threatKind: ThreatKind, revision: Int) -> APIRequestType {
        .filterSet(threatKind: threatKind, revision: revision)
    }
}
