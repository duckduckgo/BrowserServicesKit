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

public class PhishingDetectionService: PhishingDetectionServiceProtocol {
    

    public var filterSet: [Filter] = []
    public var hashPrefixes = [String]()
    var currentRevision = 0
    var apiClient: PhishingDetectionClientProtocol

    init(apiClient: PhishingDetectionClientProtocol? = nil) {
        self.apiClient = apiClient ?? PhishingDetectionAPIClient() as PhishingDetectionClientProtocol
    }
    
    public func updateFilterSet() async {
        let filterSet = await apiClient.updateFilterSet(revision: currentRevision)
        self.filterSet = filterSet
    }
    
    public func updateHashPrefixes() async {
        let hashPrefixes = await apiClient.updateHashPrefixes(revision: currentRevision)
        self.hashPrefixes = hashPrefixes
    }
    
    public func getMatches(hashPrefix: String) async -> [Match] {
        return await apiClient.getMatches(hashPrefix: hashPrefix)
    }
    
    func inFilterSet(hash: String) -> [Filter] {
        return filterSet.filter { $0.hashValue == hash }
    }
    
    public func isMalicious(url: String) async -> Bool {
        guard let hostname = URL(string: url)?.host else { return false }
        let hostnameHash = SHA256.hash(data: Data(hostname.utf8)).map { String(format: "%02hhx", $0) }.joined()
        let hashPrefix = String(hostnameHash.prefix(8))
        if hashPrefixes.contains(hashPrefix) {
            let filterHit = inFilterSet(hash: hostnameHash)
            if !filterHit.isEmpty, let regex = filterHit.first?.regex, let _ = try? NSRegularExpression(pattern: regex, options: []) {
                return true
            }
            let matches = await apiClient.getMatches(hashPrefix: hashPrefix)
            for match in matches {
                if match.hash == hostnameHash, let _ = try? NSRegularExpression(pattern: match.regex, options: []) {
                    return true
                }
            }
        }
        return false
    }

    public func writeData() {
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

    public func loadData() {
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
