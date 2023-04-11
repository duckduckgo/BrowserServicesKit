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

    func sync() async throws -> [ResultsProviding]
}

struct ResultsProvider: ResultsProviding {
    let feature: Feature

    var lastSyncTimestamp: String?

    var sent: [Syncable] = []
    var received: [Syncable] = []
}

actor Worker: WorkerProtocol {

    let dataProviders: [Feature: DataProviding]
    let storage: SecureStoring
    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating

    init(
        dataProviders: [DataProviding],
        storage: SecureStoring,
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        var providersDictionary = [Feature: DataProviding]()
        for provider in dataProviders {
            providersDictionary[provider.feature] = provider
        }
        self.dataProviders = providersDictionary
        self.storage = storage
        self.endpoints = endpoints
        self.api = api
    }

    func sync() async throws -> [ResultsProviding] {

        // Collect last sync timestamp and changes per feature
        var results = try await withThrowingTaskGroup(of: [Feature: ResultsProvider].self) { group in
            var results: [Feature: ResultsProvider] = [:]

            for dataProvider in self.dataProviders.values {
                let localChanges = try await dataProvider.changes(since: dataProvider.lastSyncTimestamp)
                let resultProvider = ResultsProvider(feature: dataProvider.feature, sent: localChanges)
                results[dataProvider.feature] = resultProvider
            }
            return results
        }

        let hasLocalChanges = results.values.contains(where: { !$0.sent.isEmpty })

        let request: HTTPRequesting = hasLocalChanges ? try makePatchRequest(with: results) : try makeGetRequest(for: Array(dataProviders.keys))
        let result: HTTPResult = try await request.execute()

        switch result.response.statusCode {
        case 200:
            guard let data = result.data else {
                throw SyncError.noResponseBody
            }
            try decodeResponse(with: data, into: &results)
            fallthrough
        case 204, 304:
            return Array(results.values)
        default:
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }
    }

    private func getToken() throws -> String {
        guard let account = try storage.account() else {
            throw SyncError.accountNotFound
        }

        guard let token = try storage.account()?.token else {
            throw SyncError.noToken
        }

        return token
    }

    private func makeGetRequest(for features: [Feature]) throws -> HTTPRequesting {
        let url = try endpoints.syncGet(features: features.map(\.name))
        return api.createRequest(
            url: url,
            method: .GET,
            headers: ["Authorization": "Bearer \(try getToken())"],
            parameters: [:],
            body: nil,
            contentType: nil
        )
    }

    private func makePatchRequest(with results: [Feature: ResultsProviding]) throws -> HTTPRequesting {
        var json = [String: Any]()
        for (feature, result) in results {
            let modelPayload: [String: Any?] = [
                "updates": result.sent.map(\.payload),
                "modified_since": dataProviders[feature]?.lastSyncTimestamp
            ]
            json[feature.name] = modelPayload
        }

        let body = try JSONSerialization.data(withJSONObject: json, options: [])
        return api.createRequest(
            url: endpoints.syncPatch,
            method: .PATCH,
            headers: ["Authorization": "Bearer \(try getToken())"],
            parameters: [:],
            body: body,
            contentType: "application/json"
        )
    }

    private func decodeResponse(with data: Data, into results: inout [Feature: ResultsProvider]) throws {
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
