//
//  ConfigurationFetching.swift
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

protocol ConfigurationFetching {
    
    func fetch(_ configurations: [Configuration], onDidStore: (() -> Void)?) async throws

}

typealias ConfigurationFetchResult = (etag: String, data: Data)

public final class ConfigurationFetcher: ConfigurationFetching {
    
    enum Error: Swift.Error {
        
        case urlSession(Swift.Error)
        case invalidResponse
        case missingEtagInResponse
        case emptyData
        case invalidStatusCode
        case invalidPayload
        
    }
    
    private var store: ConfigurationStoring
    private let userAgent: APIHeaders.UserAgent
    private let urlSession: URLSession
    private let validator: ConfigurationValidating
    
    public convenience init(store: ConfigurationStoring, userAgent: APIHeaders.UserAgent, urlSession: URLSession = .shared) {
        self.init(store: store, userAgent: userAgent, validator: ConfigurationValidator())
    }
    
    init(store: ConfigurationStoring,
         userAgent: APIHeaders.UserAgent,
         urlSession: URLSession = .shared,
         validator: ConfigurationValidating = ConfigurationValidator()) {
        self.store = store
        self.userAgent = userAgent
        self.urlSession = urlSession
        self.validator = validator
    }
    
    /**
     Downloads and stores the configurations provided in parallel.

     - Parameters:
        - configurations: An array of `Configuration` enums that need to be downloaded and stored.

     - Throws:
        If any configuration fails to fetch or validate, a corresponding error is thrown.

     - Important:
        This function uses a throwing task group to download and validate the configurations in parallel. If any of the tasks in the group throws an error, the group is cancelled and the function rethrows the error. So, if any configuration fails to fetch or validate, none of the configurations will be stored.

        The `onDidStore` closure will be called after all the configurations are successfully stored.
    */
    public func fetch(_ configurations: [Configuration], onDidStore: (() -> Void)? = nil) async throws {
        try await withThrowingTaskGroup(of: (Configuration, ConfigurationFetchResult).self) { group in
            configurations.forEach { configuration in
                group.addTask {
                    let fetchResult = try await self.fetch(from: configuration.url, withEtag: self.etag(for: configuration))
                    try self.validator.validate(fetchResult.data, for: configuration)
                    return (configuration, fetchResult)
                }
            }

            var fetchResults = [(Configuration, ConfigurationFetchResult)]()
            for try await result in group {
                fetchResults.append(result)
            }

            for (configuration, fetchResult) in fetchResults {
                try self.store(fetchResult, for: configuration)
            }
            onDidStore?()
        }
    }
    
    private func etag(for configuration: Configuration) -> String? {
        if let etag = store.loadEtag(for: configuration), store.loadData(for: configuration) != nil {
            return etag
        }
        return store.loadEmbeddedEtag(for: configuration)
    }
    
    private func fetch(from url: URL, withEtag etag: String?) async throws -> ConfigurationFetchResult {
        let configuration = APIRequest.Configuration(url: url, headers: APIHeaders(with: userAgent).defaultHeaders(with: etag))
        let request = APIRequest<ConfigurationFetchResult>(configuration: configuration, urlSession: urlSession)
        let (data, response) = try await request.fetch()

        return (etag, data)
    }

    private func store(_ result: ConfigurationFetchResult, for configuration: Configuration) throws {
        try store.saveData(result.data, for: configuration)
        try store.saveEtag(result.etag, for: configuration)
    }
    
}
