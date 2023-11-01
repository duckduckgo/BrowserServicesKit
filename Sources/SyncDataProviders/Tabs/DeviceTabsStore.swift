//
//  DeviceTabsStore.swift
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

public struct DeviceTabsInfo: Codable {
    public let deviceId: String
    public let deviceTabs: [TabInfo]

    public init(deviceId: String, deviceTabs: [TabInfo]) {
        self.deviceId = deviceId
        self.deviceTabs = deviceTabs
    }
}

public struct TabInfo: Codable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public protocol CurrentDeviceTabsSource {
    var isCurrentDeviceTabsChanged: Bool { get }
    func getCurrentDeviceTabs() async throws -> DeviceTabsInfo
}

public protocol DeviceTabsStoring: CurrentDeviceTabsSource {
    func getDeviceTabs() throws -> [DeviceTabsInfo]
    func storeDeviceTabs(_ deviceTabs: [DeviceTabsInfo]) throws
}

public class DeviceTabsStore: DeviceTabsStoring {

    let dataDirectoryURL: URL
    let tabsFileURL: URL
    let currentDeviceTabsSource: CurrentDeviceTabsSource

    public init(applicationSupportURL: URL, currentDeviceTabsSource: CurrentDeviceTabsSource) {
        self.currentDeviceTabsSource = currentDeviceTabsSource
        dataDirectoryURL = applicationSupportURL.appendingPathComponent("TabsStorage")
        tabsFileURL = dataDirectoryURL.appendingPathComponent("tabs")

        initStorage()
    }

    private func initStorage() {
        if !FileManager.default.fileExists(atPath: dataDirectoryURL.path) {
            try! FileManager.default.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: tabsFileURL.path) {
            FileManager.default.createFile(atPath: tabsFileURL.path, contents: Data())
        }
    }

    public var isCurrentDeviceTabsChanged: Bool {
        currentDeviceTabsSource.isCurrentDeviceTabsChanged
    }

    public func getCurrentDeviceTabs() async throws -> DeviceTabsInfo {
        try await currentDeviceTabsSource.getCurrentDeviceTabs()
    }

    public func getDeviceTabs() throws -> [DeviceTabsInfo] {
        let data = try Data(contentsOf: tabsFileURL)
        return data.isEmpty ? [] : try jsonDecoder.decode([DeviceTabsInfo].self, from: data)
    }

    public func storeDeviceTabs(_ deviceTabs: [DeviceTabsInfo]) throws {
        try jsonEncoder.encode(deviceTabs).write(to: tabsFileURL)
    }

    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()
}
