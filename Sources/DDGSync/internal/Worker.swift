//
//  Worker.swift
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
import Combine

/**
 * Internal interface for sync worker.
 */
protocol WorkerProtocol {
    var dataProviders: [Feature: DataProviding] { get }

    func sync() async throws
}

struct SyncResult {
    let feature: Feature
    let previousSyncTimestamp: String?
    let sent: [Syncable]

    var lastSyncTimestamp: String?
    var received: [Syncable] = []
}

actor Worker: WorkerProtocol {

    let dataProviders: [Feature: DataProviding]
    let requestMaker: SyncRequestMaking

    init(dataProviders: [DataProviding], requestMaker: SyncRequestMaking) {
        var providersDictionary = [Feature: DataProviding]()
        for provider in dataProviders {
            providersDictionary[provider.feature] = provider
        }
        self.dataProviders = providersDictionary
        self.requestMaker = requestMaker
    }

    func sync() async throws {

        // Collect last sync timestamp and changes per feature
        var results = try await withThrowingTaskGroup(of: [Feature: SyncResult].self) { group in
            var results: [Feature: SyncResult] = [:]

            for dataProvider in self.dataProviders.values {
                let previousSyncTimestamp = dataProvider.lastSyncTimestamp
                let localChanges: [Syncable] = try await {
                    if previousSyncTimestamp != nil {
                        return try await dataProvider.fetchChangedObjects()
                    }
                    return try await dataProvider.fetchAllObjects()
                }()
                let result = SyncResult(feature: dataProvider.feature, previousSyncTimestamp: previousSyncTimestamp, sent: localChanges)
                results[dataProvider.feature] = result
            }
            return results
        }

        let hasLocalChanges = results.values.contains(where: { !$0.sent.isEmpty })
        let request: HTTPRequesting = hasLocalChanges ? try requestMaker.makePatchRequest(with: results) : try requestMaker.makeGetRequest(for: Array(dataProviders.keys))
        let result: HTTPResult = try await request.execute()

        switch result.response.statusCode {
        case 200:
            guard let data = result.data else {
                throw SyncError.noResponseBody
            }
            try decodeResponse(with: data, into: &results)
            fallthrough
        case 204, 304:
            for (feature, result) in results {
                try await dataProviders[feature]?.handleSyncResult(sent: result.sent, received: result.received, timestamp: result.lastSyncTimestamp)
            }
        default:
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }
    }

    private func decodeResponse(with data: Data, into results: inout [Feature: SyncResult]) throws {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SyncError.unexpectedResponseBody
        }

        for feature in results.keys {
            guard let featurePayload = jsonObject[feature.name] as? [String: Any],
                let lastModified = featurePayload["last_modified"] as? String,
                let entries = featurePayload["entries"] as? [[String: Any]]
            else {
                throw SyncError.unexpectedResponseBody
            }
            results[feature]?.lastSyncTimestamp = lastModified
            results[feature]?.received = entries.map(Syncable.init(jsonObject:))
        }
    }
}
