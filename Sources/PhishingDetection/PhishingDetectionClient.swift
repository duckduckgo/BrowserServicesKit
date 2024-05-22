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

public enum HashPrefixResponseGeneric {
    case hashPrefixResponse(HashPrefixResponse)
    case hashPrefixUpdateResponse(HashPrefixUpdateResponse)
    
    public init(hashPrefixes: [String], revision: Int, insert: [String] = [], delete: [String] = []) {
        if insert.isEmpty && delete.isEmpty {
            self = .hashPrefixResponse(HashPrefixResponse(hashPrefixes: hashPrefixes, revision: revision))
        } else {
            self = .hashPrefixUpdateResponse(HashPrefixUpdateResponse(insert: insert, delete: delete, revision: revision))
        }
    }
}

public struct HashPrefixResponse: Decodable, Encodable {
    public var hashPrefixes: [String]
    public var revision: Int
    
    public init(hashPrefixes: [String], revision: Int) {
        self.hashPrefixes = hashPrefixes
        self.revision = revision
    }
}

public struct HashPrefixUpdateResponse: Decodable, Encodable {
    public var insert: [String]
    public var delete: [String]
    public var revision: Int
    
    public init(insert: [String], delete: [String], revision: Int) {
        self.insert = insert
        self.delete = delete
        self.revision = revision
    }
}

public enum FilterSetResponseGeneric {
    case filterSetResponse(FilterSetResponse)
    case filterSetUpdateResponse(FilterSetUpdateResponse)
    
    public init(filters: [Filter], revision: Int, insert: [Filter] = [], delete: [Filter] = []) {
        if insert.isEmpty && delete.isEmpty {
            self = .filterSetResponse(FilterSetResponse(filters: filters, revision: revision))
        } else {
            self = .filterSetUpdateResponse(FilterSetUpdateResponse(insert: insert, delete: delete, revision: revision))
        }
    }
}

public struct FilterSetResponse: Decodable, Encodable {
    public var filters: [Filter]
    public var revision: Int
    
    init(filters: [Filter], revision: Int) {
        self.filters = filters
        self.revision = revision
    }
}

public struct FilterSetUpdateResponse: Decodable, Encodable {
    public var insert: [Filter]
    public var delete: [Filter]
    public var revision: Int
    
    init(insert: [Filter], delete: [Filter], revision: Int) {
        self.insert = insert
        self.delete = delete
        self.revision = revision
    }
}


public struct MatchResponse: Codable {
    public var matches: [Match]
}


public protocol PhishingDetectionClientProtocol {
    func getFilterSet(revision: Int) async -> FilterSetResponseGeneric
    func getHashPrefixes(revision: Int) async -> HashPrefixResponseGeneric
    func getMatches(hashPrefix: String) async -> [Match]
}

class PhishingDetectionAPIClient: PhishingDetectionClientProtocol {

    enum Environment {
        case production
        case staging
    }

    enum Constants {
        static let productionEndpoint = URL(string: "https://tbd.unknown.duckduckgo.com")!
        static let stagingEndpoint = URL(string: "http://localhost:3000")!
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

    init(environment: Environment = .staging) {
        switch environment {
        case .production:
            endpointURL = Constants.productionEndpoint
        case .staging:
            endpointURL = Constants.stagingEndpoint
        }
    }

    public func getFilterSet(revision: Int) async -> FilterSetResponseGeneric {
        guard let url = createURL(baseURL: filterSetURL, revision: revision, queryItemName: "revision") else {
            logDebug("🔸 Invalid filterSet revision URL: \(revision)")
            return .filterSetResponse(FilterSetResponse(filters: [], revision: revision))
        }
        let response = await fetch(url: url, responseType: FilterSetUpdateResponse.self, fallbackResponseType: FilterSetResponse.self)
        if let updateResponse = response as? FilterSetUpdateResponse {
            return .filterSetUpdateResponse(updateResponse)
        } else if let regularResponse = response as? FilterSetResponse {
            return .filterSetResponse(regularResponse)
        }
        return .filterSetResponse(FilterSetResponse(filters: [], revision: revision))
    }

    public func getHashPrefixes(revision: Int) async -> HashPrefixResponseGeneric {
        guard let url = createURL(baseURL: hashPrefixURL, revision: revision, queryItemName: "revision") else {
            logDebug("🔸 Invalid hashPrefix revision URL: \(revision)")
            return .hashPrefixResponse(HashPrefixResponse(hashPrefixes: [], revision: revision))
        }
        let response = await fetch(url: url, responseType: FilterSetUpdateResponse.self, fallbackResponseType: FilterSetResponse.self)
        if let updateResponse = response as? HashPrefixUpdateResponse {
            return .hashPrefixUpdateResponse(updateResponse)
        } else if let fullResponse = response as? HashPrefixResponse {
            return .hashPrefixResponse(fullResponse)
        }
        return .hashPrefixResponse(HashPrefixResponse(hashPrefixes: [], revision: revision))
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

    private func fetch<T: Decodable, U: Decodable>(url: URL, responseType: T.Type, fallbackResponseType: U.Type? = nil) async -> Any? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers

        do {
            let (data, _) = try await session.data(for: request)
            if let response = try? JSONDecoder().decode(responseType, from: data) {
                return response
            } else if let fallbackResponseType = fallbackResponseType, let fallbackResponse = try? JSONDecoder().decode(fallbackResponseType, from: data) {
                return fallbackResponse
            } else {
                logDebug("🔸 Failed to decode response for \(String(describing: responseType)): \(data)")
            }
        } catch {
            logDebug("🔴 Failed to load \(String(describing: responseType)) data: \(error)")
        }
        return nil
    }
}

