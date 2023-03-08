//
//  ResponseHandler.swift
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

struct ResponseHandler: ResponseHandling {

    let persistence: LocalDataPersisting
    let crypter: Crypting

    func handleUpdates(_ data: Data) async throws {
        guard !data.isEmpty else { throw SyncError.unableToDecodeResponse("Data is empty") }
        
        let deltas = try JSONDecoder.snakeCaseKeys.decode(SyncDelta.self, from: data)
        
        var syncEvents = [SyncEvent]()
        
        deltas.bookmarks?.entries.forEach { bookmarkUpdate in
            do {
                guard let event = try bookmarkUpdateToEvent(bookmarkUpdate) else { return }
                syncEvents.append(event)
            } catch {
                // Nothing much we can do here and we don't want to break everything because of some dodgy data, but we don't lose this info either in case something more critical is going wrong.
                // TODO log this error
            }
        }
        
        try await persistence.persistEvents(syncEvents)

        // Only save this after things have been persisted
        if let bookmarksLastModified = deltas.bookmarks?.last_modified, !bookmarksLastModified.isEmpty {
            persistence.updateBookmarksLastModified(bookmarksLastModified)
        }
    }
    
    private func bookmarkUpdateToEvent(_ bookmarkUpdate: BookmarkUpdate) throws -> SyncEvent? {
        guard let id = bookmarkUpdate.id else { return nil }
        guard let encryptedTitle = bookmarkUpdate.title else { return nil }
        
        let title = try crypter.base64DecodeAndDecrypt(encryptedTitle)
        
        if bookmarkUpdate.deleted != nil {
            
            return .bookmarkDeleted(id: id)
            
        } else if bookmarkUpdate.folder != nil {
            
            return .bookmarkFolderUpdated(SavedSiteFolder(id: id,
                                         title: title,
                                         nextItem: bookmarkUpdate.next,
                                         parent: bookmarkUpdate.parent))
        } else {
            
            guard let encryptedUrl = bookmarkUpdate.page?.url else { return nil }
            let url = try crypter.base64DecodeAndDecrypt(encryptedUrl)
            let savedSite = SavedSiteItem(id: id,
                                      title: title,
                                      url: url,
                                      isFavorite: bookmarkUpdate.favorite != nil,
                                      nextFavorite: bookmarkUpdate.favorite?.next,
                                      nextItem: bookmarkUpdate.next,
                                      parent: bookmarkUpdate.parent)
            return .bookmarkUpdated(savedSite)
        }
    }
    
    struct SyncDelta: Decodable {
        
        var bookmarks: BookmarkDeltas?
        
    }

    // Not using CodingKeys to keep it simple
    // swiftlint:disable identifier_name
    struct BookmarkDeltas: Decodable {
        
        var last_modified: String?
        var entries: [BookmarkUpdate]
        
    }
    // swiftlint:enable identifier_name

}
