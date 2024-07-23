//
//  PhishingDetectionClient.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common

public struct HashPrefixResponse: Decodable, Encodable {
    public var insert: [String]
    public var delete: [String]
    public var revision: Int
    public var replace: Bool

    public init(insert: [String], delete: [String], revision: Int, replace: Bool) {
        self.insert = insert
        self.delete = delete
        self.revision = revision
        self.replace = replace
    }
}

public struct FilterSetResponse: Decodable, Encodable {
    public var insert: [Filter]
    public var delete: [Filter]
    public var revision: Int
    public var replace: Bool

    public init(insert: [Filter], delete: [Filter], revision: Int, replace: Bool) {
        self.insert = insert
        self.delete = delete
        self.revision = revision
        self.replace = replace
    }
}

public struct MatchResponse: Codable {
    public var matches: [Match]
}

public protocol PhishingDetectionClientProtocol {
    func getFilterSet(revision: Int) async -> FilterSetResponse
    func getHashPrefixes(revision: Int) async -> HashPrefixResponse
    func getMatches(hashPrefix: String) async -> [Match]
}

public class PhishingDetectionAPIClient: PhishingDetectionClientProtocol {

    public enum Environment {
        case production
        case staging
    }

    enum Constants {
        static let productionEndpoint = URL(string: "https://tbd.unknown.duckduckgo.com")!
        static let stagingEndpoint = URL(string: "https://web-use-1.duckduckgo.com/api/protection/")!
    }

    private let endpointURL: URL
    private let session: URLSession = .shared
    private var headers: [String: String]? = [:]

    var filterSetURL: URL {
        endpointURL.appendingPathComponent("filterSet")
    }

    var hashPrefixURL: URL {
        endpointURL.appendingPathComponent("hashPrefix")
    }

    var matchesURL: URL {
        endpointURL.appendingPathComponent("matches")
    }

    public init(environment: Environment = .staging) {
        switch environment {
        case .production:
            endpointURL = Constants.productionEndpoint
        case .staging:
            endpointURL = Constants.stagingEndpoint
        }
    }

    public func getFilterSet(revision: Int) async -> FilterSetResponse {
        guard let url = createURL(baseURL: filterSetURL, revision: revision, queryItemName: "revision") else {
            logDebug("🔸 Invalid filterSet revision URL: \(revision)")
            return FilterSetResponse(insert: [], delete: [], revision: revision, replace: false)
        }
        return await fetch(url: url, responseType: FilterSetResponse.self) ?? FilterSetResponse(insert: [], delete: [], revision: revision, replace: false)
    }

    public func getHashPrefixes(revision: Int) async -> HashPrefixResponse {
        guard let url = createURL(baseURL: hashPrefixURL, revision: revision, queryItemName: "revision") else {
            logDebug("🔸 Invalid hashPrefix revision URL: \(revision)")
            return HashPrefixResponse(insert: [], delete: [], revision: revision, replace: false)
        }
        return await fetch(url: url, responseType: HashPrefixResponse.self) ?? HashPrefixResponse(insert: [], delete: [], revision: revision, replace: false)
    }

    public func getMatches(hashPrefix: String) async -> [Match] {
         var urlComponents = URLComponents(url: matchesURL, resolvingAgainstBaseURL: true)
         urlComponents?.queryItems = [URLQueryItem(name: "hashPrefix", value: hashPrefix)]
         guard let url = urlComponents?.url else {
             logDebug("🔸 Invalid matches URL: \(hashPrefix)")
             return []
         }
         return await fetch(url: url, responseType: MatchResponse.self)?.matches ?? []
     }
}

// MARK: Private Methods
extension PhishingDetectionAPIClient {

    private func logDebug(_ message: String) {
        os_log(.debug, log: .phishingDetection, "\(self): \(message)")
    }

    private func createURL(baseURL: URL, revision: Int, queryItemName: String) -> URL? {
        guard revision > 0 else { return baseURL }
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = [URLQueryItem(name: queryItemName, value: String(revision))]
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
