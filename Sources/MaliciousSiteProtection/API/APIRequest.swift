//
//  APIRequest.swift
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

public protocol APIRequestProtocol {
    associatedtype ResponseType: Decodable
    var requestType: APIClient.Request { get }
}
public protocol MaliciousSiteDataChangeSetAPIRequestProtocol: APIRequestProtocol {
    init(threatKind: ThreatKind, revision: Int?)
}

public extension APIClient {
    enum Request {
        case hashPrefixSet(HashPrefixes)
        case filterSet(FilterSet)
        case matches(Matches)
    }
}
public extension APIClient.Request {
    struct HashPrefixes: MaliciousSiteDataChangeSetAPIRequestProtocol {
        public typealias ResponseType = APIClient.Response.HashPrefixesChangeSet

        public let threatKind: ThreatKind
        public let revision: Int?

        public init(threatKind: ThreatKind, revision: Int?) {
            self.threatKind = threatKind
            self.revision = revision
        }

        public var requestType: APIClient.Request {
            .hashPrefixSet(self)
        }
    }
}
extension APIRequestProtocol where Self == APIClient.Request.HashPrefixes {
    static func hashPrefixes(threatKind: ThreatKind, revision: Int?) -> Self {
        .init(threatKind: threatKind, revision: revision)
    }
}

public extension APIClient.Request {
    struct FilterSet: MaliciousSiteDataChangeSetAPIRequestProtocol {
        public typealias ResponseType = APIClient.Response.FiltersChangeSet

        public let threatKind: ThreatKind
        public let revision: Int?

        public init(threatKind: ThreatKind, revision: Int?) {
            self.threatKind = threatKind
            self.revision = revision
        }

        public var requestType: APIClient.Request {
            .filterSet(self)
        }
    }
}
extension APIRequestProtocol where Self == APIClient.Request.FilterSet {
    static func filterSet(threatKind: ThreatKind, revision: Int?) -> Self {
        .init(threatKind: threatKind, revision: revision)
    }
}

public extension APIClient.Request {
    struct Matches: APIRequestProtocol {
        public typealias ResponseType = APIClient.Response.Matches

        public let hashPrefix: String

        public var requestType: APIClient.Request {
            .matches(self)
        }
    }
}
extension APIRequestProtocol where Self == APIClient.Request.Matches {
    static func matches(hashPrefix: String) -> Self {
        .init(hashPrefix: hashPrefix)
    }
}
