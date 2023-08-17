//
//  BookmarksResponseHandler.swift
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

import Bookmarks
import CoreData
import DDGSync
import Foundation

final class BookmarksResponseHandler {
    let clientTimestamp: Date?
    let received: [SyncableBookmarkAdapter]
    let context: NSManagedObjectContext
    let shouldDeduplicateEntities: Bool

    let receivedByUUID: [String: SyncableBookmarkAdapter]
    let allReceivedIDs: Set<String>

    let topLevelFoldersSyncables: [SyncableBookmarkAdapter]
    let bookmarkSyncablesWithoutParent: [SyncableBookmarkAdapter]
    let favoritesUUIDs: [String]

    var entitiesByUUID: [String: BookmarkEntity] = [:]
    var idsOfItemsThatRetainModifiedAt = Set<String>()
    var deduplicatedFolderUUIDs = Set<String>()

    private let decrypt: (String) throws -> String

    init(received: [Syncable], clientTimestamp: Date? = nil, context: NSManagedObjectContext, crypter: Crypting, deduplicateEntities: Bool) throws {
        self.clientTimestamp = clientTimestamp
        self.received = received.map(SyncableBookmarkAdapter.init)
        self.context = context
        self.shouldDeduplicateEntities = deduplicateEntities

        let secretKey = try crypter.fetchSecretKey()
        self.decrypt = { try crypter.base64DecodeAndDecrypt($0, using: secretKey) }

        var syncablesByUUID: [String: SyncableBookmarkAdapter] = [:]
        var allUUIDs: Set<String> = []
        var childrenToParents: [String: String] = [:]
        var parentFoldersToChildren: [String: [String]] = [:]
        var favoritesUUIDs: [String] = []

        self.received.forEach { syncable in
            guard let uuid = syncable.uuid else {
                return
            }
            syncablesByUUID[uuid] = syncable

            allUUIDs.insert(uuid)
            if syncable.isFolder {
                allUUIDs.formUnion(syncable.children)
            }

            if uuid == BookmarkEntity.Constants.favoritesFolderID {
                favoritesUUIDs = syncable.children
            } else {
                if syncable.isFolder {
                    parentFoldersToChildren[uuid] = syncable.children
                }
                syncable.children.forEach { child in
                    childrenToParents[child] = uuid
                }
            }
        }

        self.allReceivedIDs = allUUIDs
        self.receivedByUUID = syncablesByUUID
        self.favoritesUUIDs = favoritesUUIDs

        let foldersWithoutParent = Set(parentFoldersToChildren.keys).subtracting(childrenToParents.keys)
        topLevelFoldersSyncables = foldersWithoutParent.compactMap { syncablesByUUID[$0] }

        bookmarkSyncablesWithoutParent = allUUIDs.subtracting(childrenToParents.keys)
            .subtracting(foldersWithoutParent + [BookmarkEntity.Constants.favoritesFolderID])
            .compactMap { syncablesByUUID[$0] }

        BookmarkEntity.fetchBookmarks(with: allReceivedIDs, in: context)
            .forEach { bookmark in
                guard let uuid = bookmark.uuid else {
                    return
                }
                entitiesByUUID[uuid] = bookmark
            }
    }

    func processReceivedBookmarks() throws {
        if received.isEmpty {
            return
        }

        for topLevelFolderSyncable in topLevelFoldersSyncables {
            try processTopLevelFolder(topLevelFolderSyncable)
        }
        try processOrphanedBookmarks()

        // populate favorites
        if !favoritesUUIDs.isEmpty {
            guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
                // Error - unable to process favorites
                return
            }

            // For non-first sync we rely fully on the server response
            if !shouldDeduplicateEntities {
                favoritesFolder.favoritesArray.forEach { $0.removeFromFavorites() }
            } else if !favoritesFolder.favoritesArray.isEmpty {
                // If we're deduplicating and there are favorires locally, we'll need to sync favorites folder back later.
                // Let's keep its modifiedAt.
                idsOfItemsThatRetainModifiedAt.insert(BookmarkEntity.Constants.favoritesFolderID)
            }

            favoritesUUIDs.forEach { uuid in
                if let bookmark = entitiesByUUID[uuid] {
                    bookmark.removeFromFavorites()
                    bookmark.addToFavorites(favoritesRoot: favoritesFolder)
                }
            }
        }
    }

    // MARK: - Private

    private func processTopLevelFolder(_ topLevelFolderSyncable: SyncableBookmarkAdapter) throws {
        guard let topLevelFolderUUID = topLevelFolderSyncable.uuid else {
            return
        }
        var queues: [[String]] = [topLevelFolderSyncable.children]
        var parentUUIDs: [String] = [topLevelFolderUUID]

        try processEntity(with: topLevelFolderSyncable)

        while !queues.isEmpty {
            var queue = queues.removeFirst()
            let parentUUID = parentUUIDs.removeFirst()
            let parent = BookmarkEntity.fetchFolder(withUUID: parentUUID, in: context)
            assert(parent != nil)

            // For non-first sync we rely fully on the server response
            if !shouldDeduplicateEntities {
                parent?.childrenArray.forEach { parent?.removeFromChildren($0) }
            }

            while !queue.isEmpty {
                let syncableUUID = queue.removeFirst()

                if let syncable = receivedByUUID[syncableUUID] {
                    try processEntity(with: syncable, parent: parent)
                    if syncable.isFolder, !syncable.children.isEmpty {
                        queues.append(syncable.children)
                        parentUUIDs.append(syncableUUID)
                    }
                    // If this entity belongs to a deduplicated non-empty folder, we'll need to sync that folder back later.
                    // Let's keep its modifiedAt.
                    if deduplicatedFolderUUIDs.contains(parentUUID) {
                        idsOfItemsThatRetainModifiedAt.insert(parentUUID)
                    }
                } else if let existingEntity = entitiesByUUID[syncableUUID] {
                    existingEntity.parent?.removeFromChildren(existingEntity)
                    parent?.addToChildren(existingEntity)
                }
            }
        }
    }

    private func processOrphanedBookmarks() throws {

        for syncable in bookmarkSyncablesWithoutParent {
            guard !syncable.isFolder else {
                assertionFailure("Bookmark folder passed to \(#function)")
                continue
            }

            try processEntity(with: syncable)
        }
    }

    private func processEntity(with syncable: SyncableBookmarkAdapter, parent: BookmarkEntity? = nil) throws {
        guard let syncableUUID = syncable.uuid else {
            return
        }

        if shouldDeduplicateEntities, let deduplicatedEntity = try BookmarkEntity.deduplicatedEntity(
            with: syncable,
            parentUUID: parent?.uuid,
            in: context,
            decryptedUsing: decrypt
        ) {

            if let oldUUID = deduplicatedEntity.uuid {
                entitiesByUUID.removeValue(forKey: oldUUID)
            }
            entitiesByUUID[syncableUUID] = deduplicatedEntity
            deduplicatedEntity.uuid = syncableUUID
            if deduplicatedEntity.isFolder, !deduplicatedEntity.childrenArray.isEmpty {
                deduplicatedFolderUUIDs.insert(syncableUUID)
            }
            if parent != nil {
                deduplicatedEntity.parent?.removeFromChildren(deduplicatedEntity)
                parent?.addToChildren(deduplicatedEntity)
            }

        } else if let existingEntity = entitiesByUUID[syncableUUID] {
            let isModifiedAfterSyncTimestamp: Bool = {
                guard let clientTimestamp, let modifiedAt = existingEntity.modifiedAt else {
                    return false
                }
                return modifiedAt > clientTimestamp
            }()
            if !isModifiedAfterSyncTimestamp {
                try existingEntity.update(with: syncable, in: context, decryptedUsing: decrypt)
            }

            if parent != nil, !existingEntity.isDeleted {
                existingEntity.parent?.removeFromChildren(existingEntity)
                parent?.addToChildren(existingEntity)
            }

        } else if !syncable.isDeleted {

            assert(syncable.uuid != BookmarkEntity.Constants.rootFolderID, "Trying to make another root folder")

            let newEntity = BookmarkEntity.make(withUUID: syncableUUID, isFolder: syncable.isFolder, in: context)
            parent?.addToChildren(newEntity)
            try newEntity.update(with: syncable, in: context, decryptedUsing: decrypt)
            entitiesByUUID[syncableUUID] = newEntity
        }
    }

}
