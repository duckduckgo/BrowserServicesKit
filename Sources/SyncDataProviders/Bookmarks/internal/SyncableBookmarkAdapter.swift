//
//  SyncableBookmarkAdapter.swift
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
import DDGSync
import Foundation

struct SyncableBookmarkAdapter {

    let syncable: Syncable

    init(syncable: Syncable) {
        self.syncable = syncable
    }

    var uuid: String? {
        syncable.payload["id"] as? String
    }

    var isDeleted: Bool {
        syncable.isDeleted
    }

    var encryptedTitle: String? {
        syncable.payload["title"] as? String
    }

    var encryptedUrl: String? {
        let page = syncable.payload["page"] as? [String: Any]
        return page?["url"] as? String
    }

    var isFolder: Bool {
        syncable.payload["folder"] != nil
    }

    var children: [String] {
        guard let folder = syncable.payload["folder"] as? [String: Any] else {
            return []
        }

        if let folderChildrenDictionary = folder["children"] as? [String: Any],
           let currentChildren = folderChildrenDictionary["current"] as? [String] {

            return currentChildren

        } else if let children = folder["children"] as? [String] {
            return children
        }

        return []
    }
}

extension Syncable {

    enum SyncableBookmarkError: Error {
        case bookmarkEntityMissingUUID
    }

    init(bookmark: BookmarkEntity, encryptedUsing encrypt: (String) throws -> String) throws {
        var payload: [String: Any] = [:]
        guard let uuid = bookmark.uuid else {
            throw SyncableBookmarkError.bookmarkEntityMissingUUID
        }

        payload["id"] = uuid

        if bookmark.isPendingDeletion {
            payload["deleted"] = ""
        } else {
            if let title = bookmark.title {
                payload["title"] = try encrypt(title)
            }
            if bookmark.isFolder {
                let children: [String] = {
                    if BookmarkEntity.Constants.favoriteFoldersIDs.contains(uuid) {
                        return bookmark.favoritesArray.compactMap(\.uuid)
                    }
                    let validChildrenIds = bookmark.childrenArray.compactMap(\.uuid)

                    // Take stubs into account - we don't want to remove them.
                    let stubIds = (bookmark.children?.array as? [BookmarkEntity] ?? []).filter({ $0.isStub }).compactMap(\.uuid)
                    return validChildrenIds + stubIds
                }()

                let lastReceivedChildren = bookmark.lastChildrenArrayReceivedFromSync ?? []
                let insert = Array(Set(children).subtracting(lastReceivedChildren))
                let remove = Array(Set(lastReceivedChildren).subtracting(children))

                var childrenDict = [String: [String]]()
                childrenDict["current"] = children
                if !insert.isEmpty {
                    childrenDict["insert"] = insert
                }
                if !remove.isEmpty {
                    childrenDict["remove"] = remove
                }

                payload["folder"] = ["children": childrenDict]

            } else if let url = bookmark.url {
                payload["page"] = ["url": try encrypt(url)]
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
