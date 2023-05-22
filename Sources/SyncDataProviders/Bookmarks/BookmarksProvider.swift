//
//  BookmarksProvider.swift
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
import Combine
import CoreData
import DDGSync
import Persistence

public final class BookmarksProvider: DataProviding {

    public init(database: CoreDataDatabase, metadataStore: SyncMetadataStore, reloadBookmarksAfterSync: @escaping () -> Void) {
        self.database = database
        self.metadataStore = metadataStore
        self.metadataStore.registerFeature(named: feature.name)
        self.reloadBookmarksAfterSync = reloadBookmarksAfterSync
        syncErrorPublisher = syncErrorSubject.eraseToAnyPublisher()
    }

    public let syncErrorPublisher: AnyPublisher<Error, Never>

    // MARK: - DataProviding

    public let feature: Feature = .init(name: "bookmarks")

    public var lastSyncTimestamp: String? {
        get {
            metadataStore.timestamp(forFeatureNamed: feature.name)
        }
        set {
            metadataStore.updateTimestamp(newValue, forFeatureNamed: feature.name)
        }
    }

    public func prepareForFirstSync() async throws {
        lastSyncTimestamp = nil

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var saveError: Error?

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            context.performAndWait {
                let fetchRequest = BookmarkEntity.fetchRequest()
                let bookmarks = (try? context.fetch(fetchRequest)) ?? []
                for bookmark in bookmarks {
                    bookmark.modifiedAt = Date()
                }

                do {
                    try context.save()
                } catch {
                    saveError = error
                }
            }

            if let saveError {
                continuation.resume(with: .failure(saveError))
            } else {
                continuation.resume()
            }
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

    public func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var saveError: Error?

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            context.performAndWait {
                while true {
                    let responseHandler = BookmarksResponseHandler(
                        received: received,
                        clientTimestamp: clientTimestamp,
                        context: context,
                        crypter: crypter,
                        deduplicateEntities: true
                    )
                    responseHandler.processReceivedBookmarks()
                    let idsOfItemsToClearModifiedAt = Set<String>()

#if DEBUG
                    willSaveContextAfterApplyingSyncResponse()
#endif
                    do {
                        let uuids = idsOfItemsToClearModifiedAt.union(Set(responseHandler.receivedByUUID.keys).subtracting(responseHandler.idsOfItemsThatRetainModifiedAt))
                        try clearModifiedAtAndSaveContext(uuids: uuids, clientTimestamp: clientTimestamp, in: context)
                        break
                    } catch {
                        if (error as NSError).code == NSManagedObjectMergeError {
                            context.reset()
                        } else {
                            saveError = error
                            break
                        }
                    }
                }
            }

            if let saveError {
                continuation.resume(throwing: saveError)
                return
            }

            if let serverTimestamp {
                lastSyncTimestamp = serverTimestamp
                reloadBookmarksAfterSync()
            }

            continuation.resume(returning: ())
        }
    }

    public func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var saveError: Error?

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            context.performAndWait {
                while true {

                    let responseHandler = BookmarksResponseHandler(
                        received: received,
                        clientTimestamp: clientTimestamp,
                        context: context,
                        crypter: crypter,
                        deduplicateEntities: false
                    )
                    let idsOfItemsToClearModifiedAt = cleanUpSentItems(sent, receivedUUIDs: Set(responseHandler.receivedByUUID.keys), clientTimestamp: clientTimestamp, in: context)
                    responseHandler.processReceivedBookmarks()

#if DEBUG
                    willSaveContextAfterApplyingSyncResponse()
#endif
                    do {
                        let uuids = idsOfItemsToClearModifiedAt.union(Set(responseHandler.receivedByUUID.keys).subtracting(responseHandler.idsOfItemsThatRetainModifiedAt))
                        try clearModifiedAtAndSaveContext(uuids: uuids, clientTimestamp: clientTimestamp, in: context)
                        break
                    } catch {
                        if (error as NSError).code == NSManagedObjectMergeError {
                            context.reset()
                        } else {
                            saveError = error
                            break
                        }
                    }

                }
            }
            if let saveError {
                continuation.resume(throwing: saveError)
                return
            }

            if let serverTimestamp {
                lastSyncTimestamp = serverTimestamp
                reloadBookmarksAfterSync()
            }

            continuation.resume(returning: ())
        }
    }

    public func handleSyncError(_ error: Error) {
        syncErrorSubject.send(error)
    }

    // MARK: - Internal

    func cleanUpSentItems(_ sent: [Syncable], receivedUUIDs: Set<String>, clientTimestamp: Date, in context: NSManagedObjectContext) -> Set<String> {
        if sent.isEmpty {
            return []
        }
        let identifiers = sent.compactMap(\.uuid)
        let bookmarks = BookmarkEntity.fetchBookmarks(with: identifiers, in: context)

        var idsOfItemsToClearModifiedAt = Set<String>()

        for bookmark in bookmarks {
            if let modifiedAt = bookmark.modifiedAt, modifiedAt > clientTimestamp {
                continue
            }
            let isLocalChangeRejectedBySync: Bool = bookmark.uuid.flatMap { receivedUUIDs.contains($0) } == true
            if bookmark.isPendingDeletion, !isLocalChangeRejectedBySync {
                context.delete(bookmark)
            } else {
                bookmark.modifiedAt = nil
                if let uuid = bookmark.uuid {
                    idsOfItemsToClearModifiedAt.insert(uuid)
                }
            }
        }

        return idsOfItemsToClearModifiedAt
    }

    /**
     * Saves context and ensures that `modifiedAt` field is cleared on affected objects.
     *
     * Context needs to be saved twice because setting `modifiedAt` to `nil` is not enough when `modifiedAt` was already `nil`.
     * In that case it would get updated to current date. So we first trigger save to populate `modifiedAt`,
     * and then we explicitly clear them for all affected objects and save again.
     */
    private func saveContextAndClearModifiedAt(_ context: NSManagedObjectContext, excludedUUIDs: Set<String> = []) throws {
        let insertedObjects = Array(context.insertedObjects).compactMap { $0 as? BookmarkEntity }
        let updatedObjects = Array(context.updatedObjects.subtracting(context.deletedObjects)).compactMap { $0 as? BookmarkEntity }

        try context.save()
        (insertedObjects + updatedObjects).forEach { bookmarkEntity in
            if let uuid = bookmarkEntity.uuid, !excludedUUIDs.contains(uuid) {
                bookmarkEntity.modifiedAt = nil
            }
        }
        try context.save()
    }

    private func clearModifiedAtAndSaveContext(uuids: Set<String>, clientTimestamp: Date, in context: NSManagedObjectContext) throws {
        let insertedObjects = Array(context.insertedObjects).compactMap { $0 as? BookmarkEntity }
        let updatedObjects = Array(context.updatedObjects.subtracting(context.deletedObjects)).compactMap { $0 as? BookmarkEntity }

        (insertedObjects + updatedObjects).forEach { bookmarkEntity in
            if let uuid = bookmarkEntity.uuid, uuids.contains(uuid) {
                bookmarkEntity.shouldManageModifiedAt = false
                if let modifiedAt = bookmarkEntity.modifiedAt, modifiedAt < clientTimestamp {
                    bookmarkEntity.modifiedAt = nil
                }
            }
        }
        try context.save()
    }

    private let database: CoreDataDatabase
    private let metadataStore: SyncMetadataStore
    private let reloadBookmarksAfterSync: () -> Void
    private let syncErrorSubject = PassthroughSubject<Error, Never>()

    // MARK: - Test support

#if DEBUG
    var willSaveContextAfterApplyingSyncResponse: () -> Void = {}
#endif

}

