//
//  Syncable+Bookmarks.swift
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
import DDGSync
import Foundation

extension Syncable {

    enum SyncableBookmarkError: Error {
        case bookmarkEntityMissingUUID
    }

    var uuid: String? {
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
