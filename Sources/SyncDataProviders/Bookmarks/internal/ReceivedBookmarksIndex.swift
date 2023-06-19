//
//  ReceivedBookmarksIndex.swift
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

struct ReceivedBookmarksIndex {
    let receivedByUUID: [String: Syncable]
    let allReceivedIDs: Set<String>

    let topLevelFoldersSyncables: [Syncable]
    let bookmarkSyncablesWithoutParent: [Syncable]
    let favoritesUUIDs: [String]

    var entitiesByUUID: [String: BookmarkEntity] = [:]

    init(received: [Syncable], in context: NSManagedObjectContext) {
        var syncablesByUUID: [String: Syncable] = [:]
        var allUUIDs: Set<String> = []
        var childrenToParents: [String: String] = [:]
        var parentFoldersToChildren: [String: [String]] = [:]
        var favoritesUUIDs: [String] = []

        received.forEach { syncable in
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
}
