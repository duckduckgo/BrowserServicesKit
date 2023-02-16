//
//  ConfigurationFetcher.swift
//  DuckDuckGo
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
import API

extension Configuration {
    
    var url: URL {
        switch self {
        case .bloomFilter: return URL(string: "https://staticcdn.duckduckgo.com/https/https-mobile-v2-bloom.bin")!
        case .bloomFilterSpec: return URL(string: "https://staticcdn.duckduckgo.com/https/https-mobile-v2-bloom-spec.json")!
        case .privacyConfig: return URL(string: "whatever")!
        }
    }
    
}

public struct ConfigurationFetchTask {
    
    let configuration: Configuration
    let url: URL?
    
    var endpoint: URL { url ?? configuration.url }
    
    public init(configuration: Configuration, url: URL? = nil) {
        self.configuration = configuration
        self.url = url
    }
    
}

typealias ConfigurationFetchResult = (etag: String, data: Data)

final class ConfigurationFetcher: ConfigurationFetching {
    
    enum Error: Swift.Error {
        
        case urlSession(Swift.Error)
        case invalidResponse
        case missingEtagInResponse
        case emptyData
        case invalidStatusCode
        
    }
    
    private var store: ConfigurationStoring
    private let onDidStore: () -> Void
    private let urlSession: URLSession
    private let userAgent: APIHeaders.UserAgent
    
    init(store: ConfigurationStoring,
         onDidStore: @escaping () -> Void,
         urlSession: URLSession = .shared,
         userAgent: APIHeaders.UserAgent) {
        self.store = store
        self.onDidStore = onDidStore
        self.urlSession = urlSession
        self.userAgent = userAgent
    }
    
    func fetch(_ fetchTasks: [ConfigurationFetchTask]) async throws {
        try await withThrowingTaskGroup(of: (Configuration, ConfigurationFetchResult).self) { group in
            fetchTasks.forEach { task in
                group.addTask {
                    (task.configuration, try await self.fetch(from: task.endpoint, withEtag: self.etag(for: task.configuration)))
                }
            }

            var fetchResults = [(Configuration, ConfigurationFetchResult)]()
            for try await result in group {
                fetchResults.append(result)
            }

            for (configuration, fetchResult) in fetchResults {
                try self.store(fetchResult, for: configuration)
            }
            onDidStore()
        }
    }
    
    private func etag(for configuration: Configuration) -> String? {
        if let etag = store.loadEtag(for: configuration), store.loadData(for: configuration) != nil {
            return etag
        }
        return store.loadEmbeddedEtag(for: configuration)
    }
    
    private func fetch(from url: URL, withEtag etag: String?) async throws -> ConfigurationFetchResult {
        let request = URLRequest.makeRequest(url: url, headers: makeHeaders(with: etag))
        let (data, response) = try await fetch(for: request)
        
        guard let response = response as? HTTPURLResponse else { throw Error.invalidResponse }
        try assertSuccessfulStatusCode(for: response)
        
        guard let etag = response.etag?.dropping(prefix: "W/") else { throw Error.missingEtagInResponse }
        guard data.count > 0 else { throw Error.emptyData }

        return (etag, data)
    }
    
    private func makeHeaders(with etag: String?) -> HTTPHeaders { APIHeaders(with: userAgent).defaultHeaders(with: etag) }
    
    private func fetch(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error {
            throw Error.urlSession(error)
        }
    }
    
    private func assertSuccessfulStatusCode(for response: HTTPURLResponse) throws {
        do {
            try response.assertStatusCode(200..<300)
        } catch {
            throw Error.invalidStatusCode
        }
    }
    
    private func store(_ result: ConfigurationFetchResult, for configuration: Configuration) throws {
        try store.saveData(result.data, for: configuration)
        try store.saveEtag(result.etag, for: configuration)
    }
    
}
