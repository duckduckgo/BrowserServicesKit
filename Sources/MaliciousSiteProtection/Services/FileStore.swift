//
//  FileStore.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import os

public protocol FileStoring {
    func write(data: Data, to filename: String)
    func read(from filename: String) -> Data?
}

public struct FileStore: FileStoring {
    private let dataStoreURL: URL

    public init() {
        let dataStoreDirectory: URL
        do {
            dataStoreDirectory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        } catch {
            Logger.dataManager.error("Error accessing application support directory: \(error.localizedDescription)")
            dataStoreDirectory = FileManager.default.temporaryDirectory
        }
        dataStoreURL = dataStoreDirectory.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: dataStoreURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.dataManager.error("Failed to create directory: \(error.localizedDescription)")
        }
    }

    public func write(data: Data, to filename: String) {
        let fileURL = dataStoreURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
        } catch {
            Logger.dataManager.error("Error writing to directory: \(error.localizedDescription)")
        }
    }

    public func read(from filename: String) -> Data? {
        let fileURL = dataStoreURL.appendingPathComponent(filename)
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            Logger.dataManager.error("Error accessing application support directory: \(error)")
            return nil
        }
    }
}
