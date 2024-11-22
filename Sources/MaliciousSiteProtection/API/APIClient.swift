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
import os
import Networking

public protocol APIClientProtocol {
    func getFilterSet(revision: Int) async -> APIClient.FiltersChangeSetResponse
    func getHashPrefixes(revision: Int) async -> APIClient.HashPrefixesChangeSetResponse
    func getMatches(hashPrefix: String) async -> [Match]
}

public protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

extension URLSessionProtocol {
    public static var defaultSession: URLSessionProtocol {
        return URLSession.shared
    }
}

public struct APIClient: APIClientProtocol {

    public enum Environment {
        case production
        case staging
    }

    enum Constants {
        static let productionEndpoint = URL(string: "https://duckduckgo.com/api/protection/")!
        static let stagingEndpoint = URL(string: "https://staging.duckduckgo.com/api/protection/")!
        enum APIPath: String {
            case filterSet
            case hashPrefix
            case matches
        }
    }

    private let endpointURL: URL
    private let session: URLSessionProtocol!
    private var headers: [String: String]? = [:]

    var filterSetURL: URL {
        endpointURL.appendingPathComponent(Constants.APIPath.filterSet.rawValue)
    }

    var hashPrefixURL: URL {
        endpointURL.appendingPathComponent(Constants.APIPath.hashPrefix.rawValue)
    }

    var matchesURL: URL {
        endpointURL.appendingPathComponent(Constants.APIPath.matches.rawValue)
    }

    public init(environment: Environment = .production, session: URLSessionProtocol = URLSession.defaultSession) {
        switch environment {
        case .production:
            endpointURL = Constants.productionEndpoint
        case .staging:
            endpointURL = Constants.stagingEndpoint
        }
        self.session = session
    }

    public func getFilterSet(revision: Int) async -> FiltersChangeSetResponse {
        guard let url = createURL(for: .filterSet, revision: revision) else {
            logDebug("🔸 Invalid filterSet revision URL: \(revision)")
            return FiltersChangeSetResponse(insert: [], delete: [], revision: revision, replace: false)
        }
        return await fetch(url: url, responseType: FiltersChangeSetResponse.self) ?? FiltersChangeSetResponse(insert: [], delete: [], revision: revision, replace: false)
    }

    public func getHashPrefixes(revision: Int) async -> HashPrefixesChangeSetResponse {
        guard let url = createURL(for: .hashPrefix, revision: revision) else {
            logDebug("🔸 Invalid hashPrefix revision URL: \(revision)")
            return HashPrefixesChangeSetResponse(insert: [], delete: [], revision: revision, replace: false)
        }
        return await fetch(url: url, responseType: HashPrefixesChangeSetResponse.self) ?? HashPrefixesChangeSetResponse(insert: [], delete: [], revision: revision, replace: false)
    }

    public func getMatches(hashPrefix: String) async -> [Match] {
        let queryItems = [URLQueryItem(name: "hashPrefix", value: hashPrefix)]
        guard let url = createURL(for: .matches, queryItems: queryItems) else {
            logDebug("🔸 Invalid matches URL: \(hashPrefix)")
            return []
        }
        return await fetch(url: url, responseType: MatchResponse.self)?.matches ?? []
    }
}

// MARK: Private Methods
extension APIClient {

    private func logDebug(_ message: String) {
        Logger.api.debug("\(message)")
    }

    private func createURL(for path: Constants.APIPath, revision: Int? = nil, queryItems: [URLQueryItem]? = nil) -> URL? {
        // Start with the base URL and append the path component
        var urlComponents = URLComponents(url: endpointURL.appendingPathComponent(path.rawValue), resolvingAgainstBaseURL: true)
        var items = queryItems ?? []
        if let revision = revision, revision > 0 {
            items.append(URLQueryItem(name: "revision", value: String(revision)))
        }
        urlComponents?.queryItems = items.isEmpty ? nil : items
        return urlComponents?.url
    }

    private func fetch<T: Decodable>(url: URL, responseType: T.Type) async -> T? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers

        do {
            let (data, _) = try await session.data(for: request)
            if let response = try? JSONDecoder().decode(responseType, from: data) {
                return response
            } else {
                logDebug("🔸 Failed to decode response for \(String(describing: responseType)): \(data)")
            }
        } catch {
            logDebug("🔴 Failed to load \(String(describing: responseType)) data: \(error)")
        }
        return nil
    }
}
