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
    @discardableResult func write(data: Data, to filename: String) -> Bool
    func read(from filename: String) -> Data?
}

struct FileStore: FileStoring, CustomDebugStringConvertible {
    private let dataStoreURL: URL

    init(dataStoreURL: URL) {
        self.dataStoreURL = dataStoreURL
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: dataStoreURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.dataManager.error("Failed to create directory: \(error.localizedDescription)")
        }
    }

    public func write(data: Data, to filename: String) -> Bool {
        let fileURL = dataStoreURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return true
        } catch {
            Logger.dataManager.error("Error writing to directory: \(error.localizedDescription)")
            return false
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

    var debugDescription: String {
        return "<\(type(of: self)) - \"\(dataStoreURL.path)\">"
    }
}
