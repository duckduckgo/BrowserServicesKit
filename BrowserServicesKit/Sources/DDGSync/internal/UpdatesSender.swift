//
//  UpdatesSender.swift
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

struct UpdatesSender: UpdatesSending {

    var offlineUpdatesFile: URL {
        fileStorageUrl.appendingPathComponent("offline-updates.json")
    }

    let fileStorageUrl: URL
    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies

    private(set) var bookmarks = [BookmarkUpdate]()

    func persistingBookmark(_ bookmark: SavedSiteItem) throws -> UpdatesSending {
        return try appendBookmark(bookmark, deleted: false)
    }

    func persistingBookmarkFolder(_ folder: SavedSiteFolder) throws -> UpdatesSending {
        return try appendFolder(folder, deleted: false)
    }

    func deletingBookmark(_ bookmark: SavedSiteItem) throws -> UpdatesSending {
        return try appendBookmark(bookmark, deleted: true)
    }

    func deletingBookmarkFolder(_ folder: SavedSiteFolder) throws -> UpdatesSending {
        return try appendFolder(folder, deleted: true)
    }

    private func appendBookmark(_ bookmark: SavedSiteItem, deleted: Bool) throws -> UpdatesSender {
        let encryptedTitle = try dependencies.crypter.encryptAndBase64Encode(bookmark.title)
        let encryptedUrl = try dependencies.crypter.encryptAndBase64Encode(bookmark.url)
        let update = BookmarkUpdate(id: bookmark.id,
                                    next: bookmark.nextItem,
                                    parent: bookmark.parent,
                                    title: encryptedTitle,
                                    page: .init(url: encryptedUrl),
                                    favorite: bookmark.isFavorite ? .init(next: bookmark.nextFavorite) : nil,
                                    folder: nil,
                                    deleted: deleted ? "" : nil)
        
        return UpdatesSender(fileStorageUrl: fileStorageUrl,
                             persistence: persistence,
                             dependencies: dependencies,
                             bookmarks: bookmarks + [update])
    }
    
    private func appendFolder(_ folder: SavedSiteFolder, deleted: Bool) throws -> UpdatesSender {
        let encryptedTitle = try dependencies.crypter.encryptAndBase64Encode(folder.title)
        let update = BookmarkUpdate(id: folder.id,
                                    next: folder.nextItem,
                                    parent: folder.parent,
                                    title: encryptedTitle,
                                    page: nil,
                                    favorite: nil,
                                    folder: .init(),
                                    deleted: deleted ? "" : nil)
        
        return UpdatesSender(fileStorageUrl: fileStorageUrl,
                             persistence: persistence,
                             dependencies: dependencies,
                             bookmarks: bookmarks + [update])
    }

    func send() async throws {
        guard let account = try dependencies.secureStore.account() else { throw SyncError.accountNotFound }
        guard let token = account.token else { throw SyncError.noToken }
 
        let updates = prepareUpdates()
        let syncUrl = dependencies.endpoints.syncPatch
    
        let jsonData = try JSONEncoder.snakeCaseKeys.encode(updates)

        switch try await send(jsonData, withAuthorization: token, toUrl: syncUrl) {
        case .success(let updates):
            if !updates.isEmpty {
                do {
                    try await dependencies.responseHandler.handleUpdates(updates)
                } catch {
                    throw error
                }
            }
            try removeOfflineFile()

        case .failure(let error):
            switch error {
            case SyncError.unexpectedStatusCode(let statusCode):
                if statusCode == 403 {
                    try dependencies.secureStore.removeAccount()
                    try removeOfflineFile()
                    throw SyncError.accountRemoved
                }
                
            default: break
            }
            
            // Save updates for later unless this was a 403
            try saveForLater(updates)
        }
    }
    
    private func prepareUpdates() -> Updates {
        if var updates = loadPreviouslyFailedUpdates() {
            updates.bookmarks.modifiedSince = persistence.bookmarksLastModified
            updates.bookmarks.updates += self.bookmarks
            return updates
        }
        return Updates(bookmarks: BookmarkUpdates(modifiedSince: persistence.bookmarksLastModified, updates: bookmarks))
    }
  
    private func loadPreviouslyFailedUpdates() -> Updates? {
        guard let data = try? Data(contentsOf: offlineUpdatesFile) else { return nil }
        return try? JSONDecoder.snakeCaseKeys.decode(Updates.self, from: data)
    }
    
    private func saveForLater(_ updates: Updates) throws {
        try JSONEncoder.snakeCaseKeys.encode(updates).write(to: offlineUpdatesFile, options: .atomic)
    }
    
    private func removeOfflineFile() throws {
        if (try? offlineUpdatesFile.checkResourceIsReachable()) == true {
            try FileManager.default.removeItem(at: offlineUpdatesFile)
        }
    }
    
    private func send(_ json: Data, withAuthorization authorization: String, toUrl url: URL) async throws -> Result<Data, Error> {
        
        let request = dependencies.api.createRequest(
            url: url,
            method: .PATCH,
            headers: ["Authorization": "Bearer \(authorization)"],
            parameters: [:],
            body: json,
            contentType: "application/json"
        )
        let result = try await request.execute()

        guard let data = result.data else {
            throw SyncError.noResponseBody
        }

        return .success(data)
    }

    struct Updates: Codable {
        var bookmarks: BookmarkUpdates
    }
    
    struct BookmarkUpdates: Codable {
        var modifiedSince: String?
        var updates: [BookmarkUpdate]
    }

}
