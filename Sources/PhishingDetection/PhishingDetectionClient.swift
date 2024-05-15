//
//  APIService.swift
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

public protocol PhishingDetectionClientProtocol {
    func updateFilterSet(revision: Int) async -> [Filter]
    func updateHashPrefixes(revision: Int) async -> [String]
    func getMatches(hashPrefix: String) async -> [Match]
}

class PhishingDetectionAPIClient: PhishingDetectionClientProtocol {
    
    public static let baseURL: URL = URL(string: "http://localhost:3000")!
    public static let session: URLSession = .shared
    var headers: [String: String]? = [:]
    
    public func updateFilterSet(revision: Int) async -> [Filter] {
        var endpoint = "filterSet"
        if revision > 0 {
            endpoint += "?revision=\(revision)"
        }
        let url = Self.baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers
        
        do {
            let (data, _) = try await Self.session.data(for: request)
            if let filterSetResponse = try? JSONDecoder().decode(FilterSetResponse.self, from: data) {
                return filterSetResponse.filters
            } else {
                print("Failed to decode response")
            }
        } catch {
            print("Failed to load: \(error)")
        }
        return []
    }
    
    public func updateHashPrefixes(revision: Int) async -> [String] {
        var endpoint = "hashPrefix"
        if revision > 0 {
            endpoint += "?revision=\(revision)"
        }
        let url = Self.baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers
        
        do {
            let (data, _) = try await Self.session.data(for: request)
            if let hashPrefixResponse = try? JSONDecoder().decode(HashPrefixResponse.self, from: data) {
                return hashPrefixResponse.hashPrefixes
            } else {
                print("Failed to decode response")
            }
        } catch {
            print("Failed to load: \(error)")
        }
        return []
    }
    
    public func getMatches(hashPrefix: String) async -> [Match] {
        let endpoint = "matches"
        let queryParams = ["hashPrefix": hashPrefix]
        var urlComponents = URLComponents(string: Self.baseURL.appendingPathComponent(endpoint).absoluteString)
        urlComponents?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = urlComponents?.url else {
            print("Invalid URL")
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers
        
        do {
            let (data, _) = try await Self.session.data(for: request)
            if let matchResponse = try? JSONDecoder().decode(MatchResponse.self, from: data) {
                return matchResponse.matches
            } else {
                print("Failed to decode response")
            }
        } catch {
            print("Failed to load: \(error)")
            return []
        }
        return []
    }
    
}
