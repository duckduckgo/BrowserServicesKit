//
//  SyncRequestMaker.swift
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

protocol SyncRequestMaking {
    func makeGetRequest(with results: [Feature: SyncResult]) throws -> HTTPRequesting
    func makePatchRequest(with results: [Feature: SyncResult]) throws -> HTTPRequesting
}

struct SyncRequestMaker: SyncRequestMaking {
    let storage: SecureStoring
    let api: RemoteAPIRequestCreating 
    let endpoints: Endpoints
    let dateFormatter = ISO8601DateFormatter()


    func makeGetRequest(with results: [Feature: SyncResult]) throws -> HTTPRequesting {
        let url = try endpoints.syncGet(features: results.keys.map(\.name))
        let timestamps = results.values.map({ $0.previousSyncTimestamp ?? "0" }).lazy.joined(separator: ",")
        return api.createAuthenticatedGetRequest(url: url, authToken: try getToken(), parameters: ["since": timestamps])
    } 

    func makePatchRequest(with results: [Feature: SyncResult]) throws -> HTTPRequesting {
        var json = [String: Any]()
        for (feature, result) in results {
            let modelPayload: [String: Any?] = [
                "updates": result.sent.map(\.payload),
                "modified_since": result.previousSyncTimestamp
            ]
            json[feature.name] = modelPayload
        }
        json["client_timestamp"] = dateFormatter.string(from: Date())

        let body = try JSONSerialization.data(withJSONObject: json, options: [])
        return api.createAuthenticatedJSONRequest(url: endpoints.syncPatch, method: .PATCH, authToken: try getToken(), json: body)
    }

    private func getToken() throws -> String {
        guard let account = try storage.account() else {
            throw SyncError.accountNotFound
        }

        guard let token = account.token else {
            throw SyncError.noToken
        }

        return token
    }
}
