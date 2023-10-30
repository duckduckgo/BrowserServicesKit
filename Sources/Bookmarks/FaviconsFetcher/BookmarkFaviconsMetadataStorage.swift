//
//  BookmarkFaviconsMetadataStorage.swift
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

public protocol BookmarkFaviconsMetadataStoring {
    func getBookmarkIDs() throws -> Set<String>
    func storeBookmarkIDs(_ ids: Set<String>) throws
}

public class BookmarkFaviconsMetadataStorage: BookmarkFaviconsMetadataStoring {

    let dataDirectoryURL: URL
    let missingIDsFileURL: URL

    public init(applicationSupportURL: URL) {
        dataDirectoryURL = applicationSupportURL.appendingPathComponent("FaviconsFetcher")
        missingIDsFileURL = dataDirectoryURL.appendingPathComponent("missingIDs")

        initStorage()
    }

    private func initStorage() {
        if !FileManager.default.fileExists(atPath: dataDirectoryURL.path) {
            try! FileManager.default.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: missingIDsFileURL.path) {
            FileManager.default.createFile(atPath: missingIDsFileURL.path, contents: Data())
        }
    }

    public func getBookmarkIDs() throws -> Set<String> {
        let data = try Data(contentsOf: missingIDsFileURL)
        guard let rawValue = String(data: data, encoding: .utf8) else {
            return []
        }
        return Set(rawValue.components(separatedBy: ","))
    }

    public func storeBookmarkIDs(_ ids: Set<String>) throws {
        try ids.joined(separator: ",").data(using: .utf8)?.write(to: missingIDsFileURL)
    }
}
