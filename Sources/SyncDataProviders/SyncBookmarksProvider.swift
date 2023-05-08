//
//  SyncBookmarksProvider.swift
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
import Bookmarks
import CoreData
import Persistence
import DDGSync

public final class SyncBookmarksProvider: DataProviding {

    public let feature: Feature = .init(name: "bookmarks")

    public var lastSyncTimestamp: String? {
        get {
            metadataStore.timestamp(forFeatureNamed: feature.name)
        }
        set {
            metadataStore.updateTimestamp(newValue, forFeatureNamed: feature.name)
        }
    }

    public init(database: CoreDataDatabase, metadataStore: SyncMetadataStore, reloadBookmarksAfterSync: @escaping () -> Void) {
        self.database = database
        self.metadataStore = metadataStore
        self.metadataStore.registerFeature(named: feature.name)
        self.reloadBookmarksAfterSync = reloadBookmarksAfterSync
    }

    public func prepareForFirstSync() {
        lastSyncTimestamp = nil
    }

    public func fetchAllObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        return await withCheckedContinuation { continuation in
            var syncableBookmarks: [Syncable] = []

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            context.performAndWait {
                let fetchRequest = BookmarkEntity.fetchRequest()
                let bookmarks = (try? context.fetch(fetchRequest)) ?? []
                syncableBookmarks = bookmarks.compactMap { try? Syncable(bookmark: $0, encryptedWith: crypter) }
            }
            continuation.resume(with: .success(syncableBookmarks))
        }
    }

    public func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        return await withCheckedContinuation { continuation in

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            var syncableBookmarks: [Syncable] = []
            context.performAndWait {
                let bookmarks = BookmarkUtils.fetchModifiedBookmarks(context)
                syncableBookmarks = bookmarks.compactMap { try? Syncable(bookmark: $0, encryptedWith: crypter) }
            }
            continuation.resume(with: .success(syncableBookmarks))
        }
    }

    public func handleSyncResult(sent: [Syncable], received: [Syncable], timestamp: String?, crypter: Crypting) async {
        await withCheckedContinuation { continuation in
            var saveError: Error?

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            context.performAndWait {
                cleanUpSentItems(sent, in: context)
                processReceivedBookmarks(received, in: context, using: crypter)

                let insertedObjects = Array(context.insertedObjects).compactMap { $0 as? BookmarkEntity }
                let updatedObjects = Array(context.updatedObjects.subtracting(context.deletedObjects)).compactMap { $0 as? BookmarkEntity }

                do {
                    try context.save()
                    (insertedObjects + updatedObjects).forEach { $0.modifiedAt = nil }
                    try context.save()
                } catch {
                    saveError = error
                }
            }
            if let saveError {
                print("SAVE ERROR", saveError)
            } else if let timestamp {
                lastSyncTimestamp = timestamp
                reloadBookmarksAfterSync()
            }

            continuation.resume()
        }
    }

    func cleanUpSentItems(_ sent: [Syncable], in context: NSManagedObjectContext) {
        if sent.isEmpty {
            return
        }
        let identifiers = sent.compactMap(\.id)
        let bookmarks = BookmarkEntity.fetchBookmarks(with: identifiers, in: context)
        for bookmark in bookmarks {
            if bookmark.isPendingDeletion {
                context.delete(bookmark)
            } else {
                bookmark.modifiedAt = nil
            }
        }
    }

    func processReceivedBookmarks(_ received: [Syncable], in context: NSManagedObjectContext, using crypter: Crypting) {
        if received.isEmpty {
            return
        }

        let metadata = ReceivedBookmarksMetadata(received: received)
        let bookmarks = BookmarkEntity.fetchBookmarks(with: metadata.receivedIDs, in: context)

        // index local bookmarks by UUID
        var existingByUUID = bookmarks.byUUID()

        // update existing local bookmarks data and store them in processedUUIDs
        processExistingEntities(bookmarks, received: received, in: context, using: crypter)

        // deduplication

        let topLevelFolderSyncables: [Syncable] = {
            if let rootFolderSyncable = metadata.receivedByID[BookmarkEntity.Constants.rootFolderID] {
                return [rootFolderSyncable]
            }
            return metadata.foldersWithoutParent.compactMap { metadata.receivedByID[$0] }
        }()

        for topLevelFolderSyncable in topLevelFolderSyncables {
            guard let topLevelFolderID = topLevelFolderSyncable.id else {
                continue
            }
            var queues: [[String]] = [topLevelFolderSyncable.children]
            var parentIDs: [String] = [topLevelFolderID]

            while !queues.isEmpty {
                var queue = queues.removeFirst()
                let parentID = parentIDs.removeFirst()
                let parent = BookmarkEntity.fetchFolder(withUUID: parentID, in: context)
                assert(parent != nil)

                while !queue.isEmpty {
                    let syncableID = queue.removeLast()
                    guard let syncable = metadata.receivedByID[syncableID] else {
                        continue
                    }

                    if let deduplicatedEntity = BookmarkEntity.deduplicatedEntity(with: syncable, parentID: parentID, in: context, using: crypter) {
                        if let oldUUID = deduplicatedEntity.uuid {
                            existingByUUID.removeValue(forKey: oldUUID)
                        }
                        existingByUUID[syncableID] = deduplicatedEntity
                        deduplicatedEntity.uuid = syncableID
                    } else if let existingEntity = existingByUUID[syncableID] {
                        try? existingEntity.update(with: syncable, in: context, using: crypter)
                    } else if !syncable.isDeleted {
                        let newEntity = BookmarkEntity.make(withUUID: syncableID, isFolder: syncable.isFolder, in: context)
                        newEntity.parent = parent
                        try? newEntity.update(with: syncable, in: context, using: crypter)
                        existingByUUID[syncableID] = newEntity
                    }
                    if syncable.isFolder, !syncable.children.isEmpty {
                        queues.append(syncable.children)
                        parentIDs.append(syncableID)
                    }
                }
            }
        }

        // at this point all new bookmarks are created

        // extract received favorites UUIDs
        let favoritesUUIDs: [String] = received.first(where: { $0.id == BookmarkEntity.Constants.favoritesFolderID })?.children ?? []
        // populate favorites
        if !favoritesUUIDs.isEmpty {
            guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
                // Error - unable to process favorites
                return
            }

            favoritesUUIDs.forEach { uuid in
                if let bookmark = existingByUUID[uuid] {
                    bookmark.removeFromFavorites()
                    bookmark.addToFavorites(favoritesRoot: favoritesFolder)
                }
            }
        }

        for folderUUID in metadata.childrenToParentFoldersMap.keys {
            if let folder = existingByUUID[folderUUID], let bookmarks = metadata.childrenToParentFoldersMap[folderUUID] {
                for bookmarkUUID in bookmarks {
                    if let bookmark = existingByUUID[bookmarkUUID] {
                        bookmark.parent = nil
                        folder.addToChildren(bookmark)
                    }
                }
            }
        }
    }

    @discardableResult
    private func processExistingEntities(
        _ bookmarks: [BookmarkEntity],
        received: [Syncable],
        in context: NSManagedObjectContext,
        using crypter: Crypting
    ) -> Set<String> {

        bookmarks.reduce(into: .init()) { partialResult, bookmark in
            guard let syncable = received.first(where: { $0.id == bookmark.uuid }) else {
                return
            }
            try? bookmark.update(with: syncable, in: context, using: crypter)
            if let uuid = bookmark.uuid {
                partialResult.insert(uuid)
            }
        }
    }

    private let database: CoreDataDatabase
    private let metadataStore: SyncMetadataStore
    private let reloadBookmarksAfterSync: () -> Void
}
