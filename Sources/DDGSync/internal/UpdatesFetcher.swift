//
//  UpdatesFetcher.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

struct UpdatesFetcher: UpdatesFetching {

    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies
    
    func fetch() async throws {
        guard let token = try dependencies.secureStore.account()?.token else {
            throw SyncError.noToken
        }
        
        switch try await send(token) {
        case .success(let updates):
            try await dependencies.responseHandler.handleUpdates(updates)

        case .failure(let error):
            switch error {
            case SyncError.unexpectedStatusCode(let statusCode):
                if statusCode == 403 {
                    try dependencies.secureStore.removeAccount()
                }
                
            default: break
            }
            throw error
        }
    }

    private func send(_ authorization: String) async throws -> Result<Data, Error> {
        let syncUrl = dependencies.endpoints.syncGet

        // A comma separated list of types
        let url = syncUrl.appendingPathComponent("bookmarks")

        var request = dependencies.api.createRequest(url: url, method: .GET)
        request.addHeader("Authorization", value: "bearer \(authorization)")

        // The since parameter should be an array of each lasted updated timestamp, but don't pass anything if any of the types are missing.
        if let bookmarksUpdatedSince = persistence.bookmarksLastModified,
           !bookmarksUpdatedSince.isEmpty {
            
            let since = [
                bookmarksUpdatedSince
            ]
            request.addParameter("since", value: since.joined(separator: ","))
            
        }

        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let data = result.data else {
            throw SyncError.noResponseBody
        }

        return .success(data)
    }

}
