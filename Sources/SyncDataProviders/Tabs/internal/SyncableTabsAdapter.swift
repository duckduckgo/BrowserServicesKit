//
//  SyncableTabsAdapter.swift
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
import Foundation

struct SyncableTabsAdapter {

    let syncable: Syncable

    init(syncable: Syncable) {
        self.syncable = syncable
    }

    var uuid: String? {
        syncable.payload["id"] as? String
    }

    var isDeleted: Bool {
        syncable.isDeleted
    }

    var encryptedDeviceTabs: String? {
        syncable.payload["device_tabs"] as? String
    }
}

extension TabInfo {
    var jsonRepresentation: [String: String] {
        ["title": title, "url": url.absoluteString]
    }

    init(json: [String: String]) throws {
        guard let title = json["title"], let urlString = json["url"], let url = URL(string: urlString) else {
            throw SyncError.accountNotFound // todo
        }
        self.init(title: title, url: url)
    }
}

extension Syncable {

    init(deviceTabsInfo: DeviceTabsInfo, lastModified: Date?, encryptedUsing encrypt: (String) throws -> String) throws {
        var payload: [String: Any] = [:]

        payload["id"] = deviceTabsInfo.deviceId

        let deviceTabsInfoData = try JSONSerialization.data(withJSONObject: deviceTabsInfo.deviceTabs.map(\.jsonRepresentation))
        if let deviceTabsInfoDataString = String(data: deviceTabsInfoData, encoding: .utf8) {
            payload["device_tabs"] = try encrypt(deviceTabsInfoDataString)
        }

        if let lastModified {
            payload["client_last_modified"] = Self.dateFormatter.string(from: lastModified)
        }
        self.init(jsonObject: payload)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }
}
