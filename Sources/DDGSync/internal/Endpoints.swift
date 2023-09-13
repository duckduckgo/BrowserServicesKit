//
//  Endpoints.swift
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

struct Endpoints {

    let baseURL: URL

    let signup: URL
    let login: URL
    let logoutDevice: URL
    let connect: URL

    let syncGet: URL
    let syncPatch: URL

    /// Constructs sync GET URL for specific data type(s), e.g. `sync/type1,type2,type3`
    func syncGet(features: [String]) throws -> URL {
        guard !features.isEmpty else {
            throw SyncError.noFeaturesSpecified
        }
        return syncGet.appendingPathComponent(features.joined(separator: ","))
    }

    init(serverEnvironment: ServerEnvironment) {
        self.init(baseURL: serverEnvironment.baseURL)
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
        signup = baseURL.appendingPathComponent("sync/signup")
        login = baseURL.appendingPathComponent("sync/login")
        logoutDevice = baseURL.appendingPathComponent("sync/logout-device")
        connect = baseURL.appendingPathComponent("sync/connect")

        syncGet = baseURL.appendingPathComponent("sync")
        syncPatch = baseURL.appendingPathComponent("sync/data")
    }
    
}
