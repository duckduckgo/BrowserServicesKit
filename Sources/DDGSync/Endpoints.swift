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

public struct Endpoints {

    let signup: URL
    let login: URL
    let logoutDevice: URL

    /// Optionally has the data type(s) appended to it, e.g. `sync/bookmarks`, `sync/type1,type2,type3`
    let syncGet: URL
    
    let syncPatch: URL
    
    init(baseUrl: URL) {
        signup = baseUrl.appendingPathComponent("sync/signup")
        login = baseUrl.appendingPathComponent("sync/login")
        logoutDevice = baseUrl.appendingPathComponent("sync/logout-device")
        syncGet = baseUrl.appendingPathComponent("sync")
        syncPatch = baseUrl.appendingPathComponent("sync/data")
    }
    
}
