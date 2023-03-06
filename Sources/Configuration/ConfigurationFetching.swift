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
import Networking

protocol ConfigurationFetching {
    
    func fetch(any configurations: [Configuration]) async throws
    func fetch(all configurations: [Configuration]) async throws

}

typealias ConfigurationFetchResult = (etag: String, data: Data?)

public final class ConfigurationFetcher: ConfigurationFetching {
    
    enum Error: Swift.Error {
        
        case apiRequest(APIRequest.Error)
        case invalidPayload
        case aggregated(errors: [Configuration: Swift.Error])
        
    }
    
    actor AggregatedError {
        
        var errors: [Configuration: Swift.Error] = [:]
        func set(error: Swift.Error, for configuration: Configuration) {
            errors[configuration] = error
        }
        
        var isEmpty: Bool { errors.isEmpty }
        
    }
    
    private var store: ConfigurationStoring
    private let urlSession: URLSession
    private let validator: ConfigurationValidating
    
    public convenience init(store: ConfigurationStoring, urlSession: URLSession = .shared) {
        self.init(store: store, validator: ConfigurationValidator())
    }
    
    init(store: ConfigurationStoring,
         validator: ConfigurationValidating = ConfigurationValidator(),
         urlSession: URLSession = .shared) {
        self.store = store
        self.validator = validator
        self.urlSession = urlSession
    }
    
    /**
     Downloads and stores the configurations provided in parallel.

     - Parameters:
        - configurations: An array of `Configuration` enums that need to be downloaded and stored.

     - Throws:
        If any configuration fails to fetch or validate, an `Error` of type `.aggregated` is thrown.
        The `.aggregated` case of the `Error` enum contains a dictionary of type `[Configuration: Error]`
        that associates each failed configuration with its corresponding error.

     - Important:
        If any task fails, the error is recorded but the group continues processing the remaining tasks.
        The task group is not cancelled automatically when a task throws an error.
     */

    private var aggregatedError = AggregatedError()
    public func fetch(any configurations: [Configuration]) async throws {
        await withTaskGroup(of: Void.self) { group in
            for configuration in configurations {
                group.addTask { [self] in
                    do {
                        print("configuration fetch: \(configuration)")
                        let fetchResult = try await fetch(from: configuration.url, withEtag: etag(for: configuration))
                        print("configuration after fetch: \(configuration)")
                        if let data = fetchResult.data {
                            try validator.validate(data, for: configuration)
                        }
                        print("configuration store: \(configuration)")
                        try store(fetchResult, for: configuration)
                    } catch {
                        print("configuration throw: \(configuration): \(error)")
                        await aggregatedError.set(error: error, for: configuration)
                    }
                }
            }
            await group.waitForAll()
        }
        
        if await !aggregatedError.isEmpty {
            throw await Error.aggregated(errors: aggregatedError.errors)
        }
    }
    
    /**
     Downloads and stores the configurations provided in parallel using a throwing task group.
     This function throws an error if any of the configurations fail to fetch or validate.

     - Parameters:
       - configurations: An array of `Configuration` enums that need to be downloaded and stored.

     - Throws:
       An error of type `Error` is thrown if any configuration fails to fetch or validate.

     - Important:
       This function uses a throwing task group to download and validate the configurations in parallel.
       If any of the tasks in the group throws an error, the group is cancelled and the function rethrows the error.
       So, if any configuration fails to fetch or validate, none of the configurations will be stored.
    */
    public func fetch(all configurations: [Configuration]) async throws {
        try await withThrowingTaskGroup(of: (Configuration, ConfigurationFetchResult).self) { group in
            configurations.forEach { configuration in
                group.addTask {
                    let fetchResult = try await self.fetch(from: configuration.url, withEtag: self.etag(for: configuration))
                    if let data = fetchResult.data {
                        try self.validator.validate(data, for: configuration)
                    }
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
        }
    }
    
    private func etag(for configuration: Configuration) -> String? {
        if let etag = store.loadEtag(for: configuration), store.loadData(for: configuration) != nil {
            return etag
        }
        return store.loadEmbeddedEtag(for: configuration)
    }
    
    private func fetch(from url: URL, withEtag etag: String?) async throws -> ConfigurationFetchResult {
        let configuration = APIRequest.Configuration(url: url, headers: APIRequest.APIHeaders().defaultHeaders(with: etag))
        let request = APIRequest(configuration: configuration, requirements: [.all], urlSession: urlSession)
        let (data, response) = try await request.fetch()
        return (response.etag!, data)
    }

    private func store(_ result: ConfigurationFetchResult, for configuration: Configuration) throws {
        if let data = result.data {
            try store.saveData(data, for: configuration)
            try store.saveEtag(result.etag, for: configuration)
        }
    }
    
}
