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
        let bookmarks = fetchBookmarks(with: identifiers, in: context)
        for bookmark in bookmarks {
            if bookmark.isPendingDeletion {
                context.delete(bookmark)
            } else {
                bookmark.modifiedAt = nil
            }
        }
    }

    func processReceivedBookmarks(_ received: [Syncable], in context: NSManagedObjectContext, using crypter: Crypting) {
        let (receivedIDs, bookmarkToFolderMap, folderToBookmarksMap) = received.indexIDs()

        if receivedIDs.isEmpty {
            return
        }

        let bookmarks = fetchBookmarks(with: receivedIDs, in: context)

        // index local bookmarks by UUID
        var existingByUUID = bookmarks.byUUID()

        // update existing local bookmarks data and store them in processedUUIDs
        var processedUUIDs = processExistingEntities(bookmarks, received: received, in: context, using: crypter)
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

            let parentFoldersTitles = parentNames(for: syncable, in: received, using: bookmarkToFolderMap)
            if let deduplicatedEntity = deduplicatedEntity(with: syncable, parentFoldersTitles: parentFoldersTitles, in: context, using: crypter) {
                if let oldUUID = deduplicatedEntity.uuid {
                    existingByUUID.removeValue(forKey: oldUUID)
                }
                existingByUUID[uuid] = deduplicatedEntity
                deduplicatedEntity.uuid = uuid
                processedUUIDs.insert(uuid)
                try? deduplicatedEntity.update(with: syncable, in: context, using: crypter)
                return false
            }

            insertedByUUID[uuid] = BookmarkEntity.make(withUUID: uuid, isFolder: syncable.isFolder, in: context)
            return true
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
                if let bookmark = insertedByUUID[uuid] ?? existingByUUID[uuid] {
                    bookmark.removeFromFavorites()
                    bookmark.addToFavorites(favoritesRoot: favoritesFolder)
                }
            }
        }

        // go through all received items and populate new bookmarks
        for syncable in validReceivedItems {
            guard let uuid = syncable.id, let bookmark = insertedByUUID[uuid], let parentUUID = bookmarkToFolderMap[uuid] else {
                continue
            }
            bookmark.parent = insertedByUUID[parentUUID] ?? existingByUUID[parentUUID]
            try? bookmark.update(with: syncable, in: context, using: crypter)
        }

        for folderUUID in folderToBookmarksMap.keys {
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

    private func processExistingEntities(_ bookmarks: [BookmarkEntity], received: [Syncable], in context: NSManagedObjectContext, using crypter: Crypting) -> Set<String> {
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

    private func fetchBookmarks(with uuids: any Sequence & CVarArg, in context: NSManagedObjectContext) -> [BookmarkEntity] {
        // fetch all local bookmarks referenced in the payload
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@", #keyPath(BookmarkEntity.uuid), uuids)
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.children), #keyPath(BookmarkEntity.favorites)]

        return (try? context.fetch(request)) ?? []
    }

    private func deduplicatedEntity(with syncable: Syncable, parentFoldersTitles: [String?], in context: NSManagedObjectContext, using crypter: Crypting) -> BookmarkEntity? {
        let title = try? crypter.base64DecodeAndDecrypt(syncable.encryptedTitle ?? "")
        if syncable.isFolder {
            return fetchFolder(withTitle: title, parentFoldersTitles: parentFoldersTitles, in: context)
        }

        let url = try? crypter.base64DecodeAndDecrypt(syncable.encryptedUrl ?? "")
        return fetchBookmark(withTitle: title, url: url, parentFoldersTitles: parentFoldersTitles, in: context)
    }

    private func fetchBookmark(withTitle title: String?, url: String?, parentFoldersTitles: [String?], in context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@", #keyPath(BookmarkEntity.title), title ?? "", #keyPath(BookmarkEntity.url), url ?? "")
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.parent)]

        let bookmarks = (try? context.fetch(request)) ?? []
        return bookmarks.first(where: { $0.parentFoldersTitles == parentFoldersTitles })
    }

    private func fetchFolder(withTitle title: String?, parentFoldersTitles: [String?], in context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES AND %K == %@", #keyPath(BookmarkEntity.isFolder), #keyPath(BookmarkEntity.title), title ?? "")
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.parent)]

        let folders = (try? context.fetch(request)) ?? []
        return folders.first(where: { $0.parentFoldersTitles == parentFoldersTitles })
    }

    private func parentNames(for syncable: Syncable, in syncables: [Syncable], using childrenToParentsMap: [String:String]) -> [String?] {
        var parentIDs = [String]()
        var currentSyncable: Syncable? = syncable
        while currentSyncable != nil {
            guard let syncableID = currentSyncable?.id, let parentID = childrenToParentsMap[syncableID] else {
                break
            }
            parentIDs.append(parentID)
            currentSyncable = syncables.first(where: { $0.id == parentID })
        }
        return parentIDs.map { parentID in
            syncables.first(where: { $0.id == parentID })?.encryptedTitle
        }
    }

    private let database: CoreDataDatabase
    private let metadataStore: SyncMetadataStore
    private let reloadBookmarksAfterSync: () -> Void
}

extension Syncable {

    var id: String? {
        payload["id"] as? String
    }

    var encryptedTitle: String? {
        payload["title"] as? String
    }

    var encryptedUrl: String? {
        let page = payload["page"] as? [String: Any]
        return page?["url"] as? String
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

    func update(with syncable: Syncable, in context: NSManagedObjectContext, using crypter: Crypting) throws {
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

    var parentFoldersTitles: [String?] {
        var names = [String?]()
        var currentParent = self.parent
        while currentParent != nil {
            names.append(currentParent?.title)
            currentParent = currentParent?.parent
        }
        return names
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

    func indexIDs() -> (allIDs: Set<String>, parentFoldersToChildren: [String: String], childrenToParents: [String: [String]]) {
        var childrenToParents: [String: String] = [:]
        var parentFoldersToChildren: [String: [String]] = [:]

        let allIDs: Set<String> = reduce(into: .init()) { partialResult, syncable in
            if let uuid = syncable.id {
                partialResult.insert(uuid)
                if syncable.isFolder {
                    partialResult.formUnion(syncable.children)
                }

                if uuid != BookmarkEntity.Constants.favoritesFolderID {
                    if syncable.isFolder {
                        parentFoldersToChildren[uuid] = syncable.children
                    }
                    syncable.children.forEach { child in
                        childrenToParents[child] = uuid
                    }
                }
            }
        }

        return (allIDs, childrenToParents, parentFoldersToChildren)
    }
}
