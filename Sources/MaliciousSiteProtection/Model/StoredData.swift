//
//  StoredData.swift
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

public protocol MaliciousSiteDataKeyProtocol: Hashable {
    associatedtype EmbeddedDataSetType: Decodable
    associatedtype DataSetType: IncrementallyUpdatableMaliciousSiteDataSet, LoadableFromEmbeddedData<EmbeddedDataSetType>

    var dataType: DataManager.StoredDataType { get }
    var threatKind: ThreatKind { get }
}

public extension DataManager {
    enum StoredDataType: Hashable, CaseIterable {
        case hashPrefixSet(HashPrefixes)
        case filterSet(FilterSet)

        enum Kind: CaseIterable {
            case hashPrefixSet, filterSet
        }
        // keep to get a compiler error when number of cases changes
        var kind: Kind {
            switch self {
            case .hashPrefixSet: .hashPrefixSet
            case .filterSet: .filterSet
            }
        }

        var dataKey: any MaliciousSiteDataKeyProtocol {
            switch self {
            case .hashPrefixSet(let key): key
            case .filterSet(let key): key
            }
        }

        public static var allCases: [DataManager.StoredDataType] {
            ThreatKind.allCases.map { threatKind in
                Kind.allCases.map { dataKind in
                    switch dataKind {
                    case .hashPrefixSet: .hashPrefixSet(.init(threatKind: threatKind))
                    case .filterSet: .filterSet(.init(threatKind: threatKind))
                    }
                }
            }.flatMap { $0 }
        }
    }
}

public extension DataManager.StoredDataType {
    struct HashPrefixes: MaliciousSiteDataKeyProtocol {
        public typealias DataSetType = HashPrefixSet

        public let threatKind: ThreatKind

        public var dataType: DataManager.StoredDataType {
            .hashPrefixSet(self)
        }
    }
}
extension MaliciousSiteDataKeyProtocol where Self == DataManager.StoredDataType.HashPrefixes {
    static func hashPrefixes(threatKind: ThreatKind) -> Self {
        .init(threatKind: threatKind)
    }
}

public extension DataManager.StoredDataType {
    struct FilterSet: MaliciousSiteDataKeyProtocol {
        public typealias DataSetType = FilterDictionary

        public let threatKind: ThreatKind

        public var dataType: DataManager.StoredDataType {
            .filterSet(self)
        }
    }
}
extension MaliciousSiteDataKeyProtocol where Self == DataManager.StoredDataType.FilterSet {
    static func filterSet(threatKind: ThreatKind) -> Self {
        .init(threatKind: threatKind)
    }
}
