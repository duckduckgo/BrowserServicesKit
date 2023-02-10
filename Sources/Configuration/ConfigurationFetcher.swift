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

fileprivate extension Configuration {
    
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
    let etag: String?
    let url: URL?
    
    fileprivate var endpoint: URL { url ?? configuration.url }
    
    public init(configuration: Configuration, etag: String? = nil, url: URL? = nil) {
        self.configuration = configuration
        self.etag = etag
        self.url = url
    }
    
}

typealias ConfigurationFetchResult = (etag: String, data: Data)

final class ConfigurationFetcher: ConfigurationFetching {
    
    enum Error: Swift.Error {
        
        case invalidResponse
        case missingEtagInResponse
        case invalidStatusCode
        
    }
    
    private let store: ConfigurationStoring
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
                    let result = try await self.fetch(from: task.endpoint,
                                                      withEtag: task.etag)
                    return (task.configuration, result)
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
    
    private func fetch(from url: URL, withEtag etag: String?) async throws -> ConfigurationFetchResult {
        let request = URLRequest.makeRequest(url: url, headers: makeHeaders(with: etag))
        // todo: os_log
        let (data, response) = try await urlSession.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        try assertSuccessfulStatusCode(for: response)

        guard let etag = response.etag?.dropping(prefix: "W/") else {
            throw Error.missingEtagInResponse
        }

        return (etag, data)
    }
    
    private func makeHeaders(with etag: String?) -> HTTPHeaders { APIHeaders(with: userAgent).defaultHeaders(with: etag) }
    
    private func assertSuccessfulStatusCode(for response: HTTPURLResponse) throws {
        do {
            try response.assertStatusCode(200..<300)
        } catch {
            throw Error.invalidStatusCode
        }
    }
    
    private func store(_ result: ConfigurationFetchResult, for configuration: Configuration) throws {
        try store.saveData(result.data, for: configuration)
    }
    
}
