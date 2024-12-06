//
//  APIClient.swift
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

import Common
import Foundation
import Networking

extension APIClient {
    // used internally for testing
    protocol Mockable {
        func load<Request: APIClient.Request>(_ requestConfig: Request) async throws -> Request.Response
    }
}
extension APIClient: APIClient.Mockable {}

public protocol APIClientEnvironment {
    func queryItems(for requestType: APIRequestType) -> QueryItems
    func headers(for requestType: APIRequestType) -> APIRequestV2.HeadersV2
    func url(for requestType: APIRequestType) -> URL
}

public extension MaliciousSiteDetector {
    enum APIEnvironment: APIClientEnvironment {

        case production
        case staging

        var endpoint: URL {
            switch self {
            case .production: URL(string: "https://duckduckgo.com/api/protection/")!
            case .staging: URL(string: "https://staging.duckduckgo.com/api/protection/")!
            }
        }

        var defaultHeaders: APIRequestV2.HeadersV2 {
            .init(userAgent: Networking.APIRequest.Headers.userAgent)
        }

        enum APIPath {
            static let filterSet = "filterSet"
            static let hashPrefix = "hashPrefix"
            static let matches = "matches"
        }

        enum QueryParameter {
            static let category = "category"
            static let revision = "revision"
            static let hashPrefix = "hashPrefix"
        }

        public func queryItems(for requestType: APIRequestType) -> QueryItems {
            switch requestType {
            case .hashPrefixSet(let configuration):
                return [QueryParameter.category: configuration.threatKind.rawValue,
                        QueryParameter.revision: (configuration.revision ?? 0).description]
            case .filterSet(let configuration):
                return [QueryParameter.category: configuration.threatKind.rawValue,
                        QueryParameter.revision: (configuration.revision ?? 0).description]
            case .matches(let configuration):
                return [QueryParameter.hashPrefix: configuration.hashPrefix]
            }
        }

        public func url(for requestType: APIRequestType) -> URL {
            switch requestType {
            case .hashPrefixSet(_):
                endpoint.appendingPathComponent(APIPath.hashPrefix)
            case .filterSet(_):
                endpoint.appendingPathComponent(APIPath.filterSet)
            case .matches(_):
                endpoint.appendingPathComponent(APIPath.matches)
            }
        }

        public func headers(for requestType: APIRequestType) -> APIRequestV2.HeadersV2 {
            defaultHeaders
        }
    }

}

struct APIClient {

    let environment: APIClientEnvironment
    private let service: APIService

    init(environment: APIClientEnvironment, service: APIService = DefaultAPIService(urlSession: .shared)) {
        self.environment = environment
        self.service = service
    }

    func load<R: Request>(_ requestConfig: R) async throws -> R.Response {
        let requestType = requestConfig.requestType
        let headers = environment.headers(for: requestType)
        let url = environment.url(for: requestType)
        let queryItems = environment.queryItems(for: requestType)

        let apiRequest = APIRequestV2(url: url, queryItems: queryItems, headers: headers, timeoutInterval: requestConfig.timeout ?? 60)!
        let response = try await service.fetch(request: apiRequest)
        let result: R.Response = try response.decodeBody()

        return result
    }

}

// MARK: - Convenience
extension APIClient.Mockable {
    func filtersChangeSet(for threatKind: ThreatKind, revision: Int) async throws -> APIClient.Response.FiltersChangeSet {
        let result = try await load(.filterSet(threatKind: threatKind, revision: revision))
        return result
    }

    func hashPrefixesChangeSet(for threatKind: ThreatKind, revision: Int) async throws -> APIClient.Response.HashPrefixesChangeSet {
        let result = try await load(.hashPrefixes(threatKind: threatKind, revision: revision))
        return result
    }

    func matches(forHashPrefix hashPrefix: String) async throws -> APIClient.Response.Matches {
        let result = try await load(.matches(hashPrefix: hashPrefix))
        return result
    }
}
