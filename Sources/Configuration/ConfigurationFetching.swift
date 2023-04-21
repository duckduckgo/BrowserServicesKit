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

    func fetch(_ configuration: Configuration) async throws
    func fetch(all configurations: [Configuration]) async throws

}

typealias ConfigurationFetchResult = (etag: String, data: Data?)

public final class ConfigurationFetcher: ConfigurationFetching {
    
    public enum Error: Swift.Error {
        
        case apiRequest(APIRequest.Error)
        case invalidPayload

    }

    private var store: ConfigurationStoring
    private let validator: ConfigurationValidating
    private let urlSession: URLSession
    private let getLog: () -> OSLog
    private var log: OSLog {
        getLog()
    }

    public convenience init(store: ConfigurationStoring,
                            urlSession: URLSession = .shared,
                            log: @escaping @autoclosure () -> OSLog = .disabled,
                            eventMapping: EventMapping<ConfigurationDebugEvents>? = nil) {
        let validator = ConfigurationValidator(eventMapping: eventMapping)
        self.init(store: store, validator: validator, log: log())
    }
    
    init(store: ConfigurationStoring,
         validator: ConfigurationValidating,
         urlSession: URLSession = .shared,
         log: @escaping @autoclosure () -> OSLog = .disabled) {
        self.store = store
        self.validator = validator
        self.urlSession = urlSession
        self.getLog = log
    }

    /**
    Downloads and stores a single configuration specified by the Configuration enum provided in the configuration parameter.
    This function throws an error if the configuration fails to fetch or validate.

    - Parameters:
      - configuration: A Configuration enum that needs to be downloaded and stored.

    - Throws:
      An error of type Error is thrown if the configuration fails to fetch or validate.
    */
    public func fetch(_ configuration: Configuration) async throws {
        let fetchResult = try await fetch(from: configuration.url, withEtag: etag(for: configuration), requirements: .default)
        if let data = fetchResult.data {
            try validator.validate(data, for: configuration)
        }
        try store(fetchResult, for: configuration)
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
                    let fetchResult = try await self.fetch(from: configuration.url, withEtag: self.etag(for: configuration), requirements: .all)
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
    
    private func fetch(from url: URL, withEtag etag: String?, requirements: APIResponseRequirements) async throws -> ConfigurationFetchResult {
        let configuration = APIRequest.Configuration(url: url,
                                                     headers: APIRequest.Headers().default(with: etag),
                                                     cachePolicy: .reloadIgnoringLocalCacheData)
        let log = log
        let request = APIRequest(configuration: configuration, requirements: requirements, urlSession: urlSession, log: log)
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
