//
//  PhishingService.swift
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
import BrowserServicesKit
import CryptoKit

public protocol PhishingDetectionServiceProtocol {
    func updateFilterSet() async
    func updateHashPrefixes() async
    func getMatches(hashPrefix: String) async -> [Match]
    func isMalicious(url: String) async -> Bool
}

public struct HashPrefixResponse: Decodable, Encodable {
    public var hashPrefixes: [String]
    public var revision: Int
}

public struct FilterSetResponse: Decodable, Encodable {
    public var filters: [Filter]
    public var revision: Int
}

public struct Filter: Decodable, Encodable {
    public var hashValue: String
    public var regex: String

    enum CodingKeys: String, CodingKey {
        case hashValue = "hash"
        case regex
    }
}

public struct MatchResponse: Decodable, Encodable {
    public var matches: [Match]
}

public struct Match: Decodable, Encodable {
    var hostname: String
    var url: String
    var regex: String
    var hash: String
}

class PhishingDetectionService: APIService {
    
    static let baseURL: URL = URL(string: "http://localhost:3000")!
    static let session: URLSession = .shared
    var currentRevision = 0
    var filterSet: [Filter] = []
    var hashPrefixes = [String]()
    var headers: [String: String]? = [:]
    
    func updateFilterSet() async {
        var endpoint = "filterSet"
        if currentRevision != 0 {
            endpoint += "?revision=\(currentRevision)"
        }
        let result: Result<FilterSetResponse, APIServiceError> = await Self.executeAPICall(method: "GET", endpoint: endpoint, headers: headers, body: nil)
        
        switch result {
        case .success(let filterSetResponse):
            self.filterSet = filterSetResponse.filters
        case .failure(let error):
            print("Failed to load: \(error)")
        }
    }
    
    func updateHashPrefixes() async {
        var endpoint = "hashPrefix"
        if currentRevision != 0 {
            endpoint += "?revision=\(currentRevision)"
        }
        let result: Result<HashPrefixResponse, APIServiceError> = await Self.executeAPICall(method: "GET", endpoint: endpoint, headers: headers, body: nil)
        
        switch result {
        case .success(let filterSetResponse):
            self.hashPrefixes = filterSetResponse.hashPrefixes
        case .failure(let error):
            print("Failed to load: \(error)")
        }
    }
    
    func getMatches(hashPrefix: String) async -> [Match] {
        let endpoint = "matches"
        let queryParams = ["hashPrefix": hashPrefix]
        let result: Result<MatchResponse, APIServiceError> = await Self.executeAPICall(method: "GET", endpoint: endpoint, headers: headers, body: nil, queryParameters: queryParams)
        
        switch result {
        case .success(let matchResponse):
            return matchResponse.matches
        case .failure(let error):
            print("Failed to load: \(error)")
            return []
        }
    }
    
    func inFilterSet(hash: String) -> [Filter] {
        return filterSet.filter { $0.hashValue == hash }
    }
    
    func isMalicious(url: String) async -> Bool {
        guard let hostname = URL(string: url)?.host else { return false }
        let hostnameHash = SHA256.hash(data: Data(hostname.utf8)).map { String(format: "%02hhx", $0) }.joined()
        let hashPrefix = String(hostnameHash.prefix(8))
        if hashPrefixes.contains(hashPrefix) {
            let filterHit = inFilterSet(hash: hostnameHash)
            if !filterHit.isEmpty, let regex = filterHit.first?.regex, let _ = try? NSRegularExpression(pattern: regex, options: []) {
                return true
            }
            let matches = await getMatches(hashPrefix: hashPrefix)
            for match in matches {
                if match.hash == hostnameHash, let _ = try? NSRegularExpression(pattern: match.regex, options: []) {
                    return true
                }
            }
        }
        return false
    }

    func writeData() {
        let encoder = JSONEncoder()
        do {
            let hashPrefixesData = try encoder.encode(hashPrefixes)
            let filterSetData = try encoder.encode(filterSet)
            try hashPrefixesData.write(to: URL(fileURLWithPath: "/tmp/hashPrefixes.json"))
            try filterSetData.write(to: URL(fileURLWithPath: "/tmp/filterSet.json"))
        } catch {
            print("Error saving phishing protection data: \(error)")
        }
    }

    func loadData() {
        let decoder = JSONDecoder()
        do {
            let hashPrefixesData = try Data(contentsOf: URL(fileURLWithPath: "/tmp/hashPrefixes.json"))
            let filterSetData = try Data(contentsOf: URL(fileURLWithPath: "/tmp/filterSet.json"))
            hashPrefixes = try decoder.decode([String].self, from: hashPrefixesData)
            filterSet = try decoder.decode([Filter].self, from: filterSetData)
        } catch {
            print("Error loading phishing protection data: \(error)")
        }
    }
    
}
