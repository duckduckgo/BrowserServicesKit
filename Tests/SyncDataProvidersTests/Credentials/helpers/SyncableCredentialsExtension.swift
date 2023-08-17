//
//  SyncableCredentialsExtension.swift
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

import BrowserServicesKit
import DDGSync

extension Syncable {

    static func credentials(
        _ title: String? = nil,
        id: String,
        domain: String? = nil,
        username: String? = nil,
        password: String? = nil,
        notes: String? = nil,
        nullifyOtherFields: Bool = false,
        lastModified: String? = nil,
        isDeleted: Bool = false
    ) -> Syncable {

        let defaultValue: Any = (nullifyOtherFields ? nil : id) as Any

        var json: [String: Any] = [
            "id": id,
            "title": title ?? defaultValue,
            "domain": domain ?? defaultValue,
            "username": username ?? defaultValue,
            "password": password ?? defaultValue,
            "notes": notes ?? defaultValue,
            "client_last_modified": "1234"
        ]
        if isDeleted {
            json["deleted"] = ""
        }
        return .init(jsonObject: json)
    }
}
