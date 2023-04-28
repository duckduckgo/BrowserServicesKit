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

    public func prepareForFirstSync() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            lastSyncTimestamp = nil
            var saveError: Error?

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            context.performAndWait {
                let fetchRequest = BookmarkEntity.fetchRequest()
                let bookmarks = (try? context.fetch(fetchRequest)) ?? []
                bookmarks.forEach { $0.modifiedAt = Date() }

                do {
                    try context.save()
                } catch {
                    saveError = error
                }
            }
            if let saveError {
                print("SAVE ERROR", saveError)
                continuation.resume(throwing: saveError)
            } else {
                continuation.resume()
            }
        }
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
        let identifiers = sent.compactMap(\.id)
        let bookmarks = fetchBookmarks(with: identifiers, in: context)
        bookmarks.forEach { $0.modifiedAt = nil }

        let bookmarksPendingDeletion = BookmarkUtils.fetchBookmarksPendingDeletion(context)

        for bookmark in bookmarksPendingDeletion {
            context.delete(bookmark)
        }
    }

    func processReceivedBookmarks(_ received: [Syncable], in context: NSManagedObjectContext, using crypter: Crypting) {
        let receivedIDs: Set<String> = received.reduce(into: .init()) { partialResult, syncable in
            if let uuid = syncable.id {
                partialResult.insert(uuid)
            }
            if syncable.isFolder {
                partialResult.formUnion(syncable.children)
            }
        }
        if receivedIDs.isEmpty {
            return
        }
        guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
            return
        }

        let bookmarks = fetchBookmarks(with: receivedIDs, in: context)

        // index local bookmarks by UUID
        var existingByUUID = bookmarks.byUUID()

        // update existing local bookmarks data and store them in processedUUIDs
        let processedUUIDs: [String] = bookmarks.reduce(into: .init()) { partialResult, bookmark in
            guard let syncable = received.first(where: { $0.id == bookmark.uuid }) else {
                return
            }
            try? bookmark.update(with: syncable, in: context, using: crypter, existing: &existingByUUID)
            if let uuid = bookmark.uuid {
                partialResult.append(uuid)
            }
        }

        // extract received favorites UUIDs
        let favoritesUUIDs: [String] = received.first(where: { $0.id == BookmarkEntity.Constants.favoritesFolderID })?.children ?? []
        var insertedByUUID = [String: BookmarkEntity]()

        // go through all received items and create new bookmarks as needed
        // filter out deleted objects from received items (they are already gone locally)
        let validReceivedItems: [Syncable] = received.filter { syncable in
            guard let uuid = syncable.id, !syncable.isDeleted else {
                return false
            }
            if processedUUIDs.contains(uuid) {
                return true
            }

            insertedByUUID[uuid] = BookmarkEntity.make(withUUID: uuid, isFolder: syncable.isFolder, in: context)
            return true
        }

        // at this point all new bookmarks are created
        // populate favorites
        favoritesUUIDs.forEach { uuid in
            if let bookmark = insertedByUUID[uuid] ?? existingByUUID[uuid] {
                bookmark.removeFromFavorites()
                bookmark.addToFavorites(favoritesRoot: favoritesFolder)
            }
        }

        let bookmarkToFolderMap = received.mapParentFolders()
        let folderToBookmarksMap = received.mapChildren()

        // go through all received items and populate new bookmarks
        for syncable in validReceivedItems {
            guard let uuid = syncable.id, let bookmark = insertedByUUID[uuid], let parentUUID = bookmarkToFolderMap[uuid] else {
                continue
            }
            bookmark.parent = insertedByUUID[parentUUID] ?? existingByUUID[parentUUID]
            try? bookmark.update(with: syncable, in: context, using: crypter, existing: &existingByUUID)
        }

        for folderUUID in bookmarkToFolderMap.values {
            if let folder = existingByUUID[folderUUID] ?? insertedByUUID[folderUUID], let bookmarks = folderToBookmarksMap[folderUUID] {
                for bookmarkUUID in bookmarks {
                    if let bookmark = insertedByUUID[bookmarkUUID] ?? existingByUUID[bookmarkUUID] {
                        bookmark.parent = nil
                        folder.addToChildren(bookmark)
                    }
                }
            }
        }
    }

    private func fetchBookmarks(with uuids: any Sequence & CVarArg, in context: NSManagedObjectContext) -> [BookmarkEntity] {
        // fetch all local bookmarks referenced in the payload
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@", #keyPath(BookmarkEntity.uuid), uuids)
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.children), #keyPath(BookmarkEntity.favorites)]

        return (try? context.fetch(request)) ?? []
    }

    private let database: CoreDataDatabase
    private let metadataStore: SyncMetadataStore
    private let reloadBookmarksAfterSync: () -> Void
}

extension Syncable {

    var id: String? {
        payload["id"] as? String
    }

    var isFolder: Bool {
        payload["folder"] != nil
    }

    var children: [String] {
        guard let folder = payload["folder"] as? [String: Any], let folderChildren = folder["children"] as? [String] else {
            return []
        }
        return folderChildren
    }

    var isDeleted: Bool {
        payload["deleted"] != nil
    }

    init(bookmark: BookmarkEntity, encryptedWith crypter: Crypting) throws {
        var payload: [String: Any] = [:]
        payload["id"] = bookmark.uuid!
        if bookmark.isPendingDeletion {
            payload["deleted"] = ""
        } else {
            if let title = bookmark.title {
                payload["title"] = try crypter.encryptAndBase64Encode(title)
            }
            if bookmark.isFolder {
                if bookmark.uuid == BookmarkEntity.Constants.favoritesFolderID {
                    payload["folder"] = [
                        "children": bookmark.favoritesArray.map(\.uuid)
                    ]
                } else {
                    payload["folder"] = [
                        "children": bookmark.childrenArray.map(\.uuid)
                    ]
                }
            } else if let url = bookmark.url {
                payload["page"] = ["url": try crypter.encryptAndBase64Encode(url)]
            }
            if let modifiedAt = bookmark.modifiedAt {
                payload["client_last_modified"] = Self.dateFormatter.string(from: modifiedAt)
            }
        }
        self.init(jsonObject: payload)
    }

    private static var dateFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }
}

extension BookmarkEntity {

    static func make(withUUID uuid: String, isFolder: Bool, in context: NSManagedObjectContext) -> BookmarkEntity {
        let bookmark = BookmarkEntity(context: context)
        bookmark.uuid = uuid
        bookmark.isFolder = isFolder
        return bookmark
    }

    func update(with syncable: Syncable, in context: NSManagedObjectContext, using crypter: Crypting, existing: inout [String: BookmarkEntity]) throws {
        let payload = syncable.payload
        guard payload["deleted"] == nil else {
            context.delete(self)
            return
        }

        modifiedAt = nil

        if let encryptedTitle = payload["title"] as? String {
            title = try crypter.base64DecodeAndDecrypt(encryptedTitle)
        }

        if !isFolder {
            if let page = payload["page"] as? [String: Any], let encryptedUrl = page["url"] as? String {
                url = try crypter.base64DecodeAndDecrypt(encryptedUrl)
            }
        }

    }
}

extension Array where Element == BookmarkEntity {

    func byUUID() -> [String: BookmarkEntity] {
        reduce(into: .init()) { partialResult, bookmark in
            guard let uuid = bookmark.uuid else {
                return
            }
            partialResult[uuid] = bookmark
        }
    }
}

extension Array where Element == Syncable {

    func mapParentFolders() -> [String: String] {
        var folders: [String: String] = [:]

        forEach { syncable in
            if let folderUUID = syncable.id, folderUUID != BookmarkEntity.Constants.favoritesFolderID {
                syncable.children.forEach { child in
                    folders[child] = folderUUID
                }
            }
        }

        return folders
    }

    func mapChildren() -> [String: [String]] {
        var children: [String: [String]] = [:]

        forEach { syncable in
            if let folderUUID = syncable.id, folderUUID != BookmarkEntity.Constants.favoritesFolderID {
                children[folderUUID] = syncable.children
            }
        }

        return children
    }
}
