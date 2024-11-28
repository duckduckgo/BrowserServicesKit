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

public protocol APIClientProtocol {
    func load<Request: APIRequestProtocol>(_ requestConfig: Request) async throws -> Request.ResponseType
}

public extension APIClientProtocol where Self == APIClient {
    static var production: APIClientProtocol { APIClient(environment: .production) }
    static var staging: APIClientProtocol { APIClient(environment: .staging) }
}

public protocol APIClientEnvironment {
    func headers(for request: APIClient.Request) -> APIRequestV2.HeadersV2
    func url(for request: APIClient.Request) -> URL
    func timeout(for request: APIClient.Request) -> TimeInterval
}

public extension APIClient {
    enum DefaultEnvironment: APIClientEnvironment {

        case production
        case staging

        var endpoint: URL {
            switch self {
            case .production: URL(string: "https://duckduckgo.com/api/protection/")!
            case .staging: URL(string: "https://staging.duckduckgo.com/api/protection/")!
            }
        }

        var defaultHeaders: APIRequestV2.HeadersV2 {
            .init(userAgent: APIRequest.Headers.userAgent)
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

        public func url(for request: APIClient.Request) -> URL {
            switch request {
            case .hashPrefixSet(let configuration):
                endpoint.appendingPathComponent(APIPath.hashPrefix).appendingParameters([
                    QueryParameter.category: configuration.threatKind.rawValue,
                    QueryParameter.revision: (configuration.revision ?? 0).description,
                ])
            case .filterSet(let configuration):
                endpoint.appendingPathComponent(APIPath.filterSet).appendingParameters([
                    QueryParameter.category: configuration.threatKind.rawValue,
                    QueryParameter.revision: (configuration.revision ?? 0).description,
                ])
            case .matches(let configuration):
                endpoint.appendingPathComponent(APIPath.matches).appendingParameter(name: QueryParameter.hashPrefix, value: configuration.hashPrefix)
            }
        }

        public func headers(for request: APIClient.Request) -> APIRequestV2.HeadersV2 {
            defaultHeaders
        }

        public func timeout(for request: APIClient.Request) -> TimeInterval {
            switch request {
            case .hashPrefixSet, .filterSet: 60
            //  This could block navigation so we should favour navigation loading if the backend is degraded.
            // On Android we're looking at a maximum 1 second timeout for this request.
            case .matches: 1
            }
        }
    }

}

public struct APIClient: APIClientProtocol {

    let environment: APIClientEnvironment
    private let service: APIService

    public init(environment: Self.DefaultEnvironment = .production, service: APIService = DefaultAPIService(urlSession: .shared)) {
        self.init(environment: environment as APIClientEnvironment, service: service)
    }

    public init(environment: APIClientEnvironment, service: APIService) {
        self.environment = environment
        self.service = service
    }

    public func load<Request: APIRequestProtocol>(_ requestConfig: Request) async throws -> Request.ResponseType {
        let requestType = requestConfig.requestType
        let headers = environment.headers(for: requestType)
        let url = environment.url(for: requestType)
        let timeout = environment.timeout(for: requestType)

        let apiRequest = APIRequestV2(url: url, method: .get, headers: headers, timeoutInterval: timeout)
        let response = try await service.fetch(request: apiRequest)
        let result: Request.ResponseType = try response.decodeBody()

        return result
    }

}

// MARK: - Convenience
extension APIClientProtocol {
    public func filtersChangeSet(for threatKind: ThreatKind, revision: Int) async throws -> APIClient.Response.FiltersChangeSet {
        let result = try await load(.filterSet(threatKind: threatKind, revision: revision))
        return result
    }

    public func hashPrefixesChangeSet(for threatKind: ThreatKind, revision: Int) async throws -> APIClient.Response.HashPrefixesChangeSet {
        let result = try await load(.hashPrefixes(threatKind: threatKind, revision: revision))
        return result
    }

    public func matches(forHashPrefix hashPrefix: String) async throws -> APIClient.Response.Matches {
        let result = try await load(.matches(hashPrefix: hashPrefix))
        return result
    }
}
