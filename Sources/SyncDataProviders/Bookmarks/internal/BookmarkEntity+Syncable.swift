//
//  BookmarkEntity+Syncable.swift
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

extension BookmarkEntity {

    static func make(withUUID uuid: String, isFolder: Bool, in context: NSManagedObjectContext) -> BookmarkEntity {
        let bookmark = BookmarkEntity(context: context)
        bookmark.uuid = uuid
        bookmark.isFolder = isFolder
        return bookmark
    }

    static func fetchBookmarks(with uuids: any Sequence & CVarArg, in context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@", #keyPath(BookmarkEntity.uuid), uuids)
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.children), #keyPath(BookmarkEntity.favorites)]

        return (try? context.fetch(request)) ?? []
    }

    static func fetchBookmark(withTitle title: String?, url: String?, in context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@", #keyPath(BookmarkEntity.title), title ?? "", #keyPath(BookmarkEntity.url), url ?? "")
        request.fetchLimit = 1

        return (try? context.fetch(request))?.first
    }

    static func fetchFolder(withTitle title: String?, parentFoldersTitles: [String?], in context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES AND %K == %@", #keyPath(BookmarkEntity.isFolder), #keyPath(BookmarkEntity.title), title ?? "")
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.parent)]

        let folders = (try? context.fetch(request)) ?? []
        return folders.first(where: { $0.parentFoldersTitles == parentFoldersTitles })
    }

    static func deduplicatedEntity(with syncable: Syncable, parentFoldersTitles: [String?], in context: NSManagedObjectContext, using crypter: Crypting) -> BookmarkEntity? {
        let title = try? crypter.base64DecodeAndDecrypt(syncable.encryptedTitle ?? "")
        if syncable.isFolder {
            return fetchFolder(withTitle: title, parentFoldersTitles: parentFoldersTitles, in: context)
        }

        let url = try? crypter.base64DecodeAndDecrypt(syncable.encryptedUrl ?? "")
        return fetchBookmark(withTitle: title, url: url, in: context)
    }

    static func fetchFolder(withTitle title: String?, parentUUID: String?, in context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES AND %K == %@", #keyPath(BookmarkEntity.isFolder), #keyPath(BookmarkEntity.title), title ?? "")
        request.returnsObjectsAsFaults = false
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.parent)]

        let folders = (try? context.fetch(request)) ?? []
        return folders.first(where: { $0.parent?.uuid == parentUUID })
    }

    static func fetchFolder(withUUID uuid: String, in context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES AND %K == %@", #keyPath(BookmarkEntity.isFolder), #keyPath(BookmarkEntity.uuid), uuid)
        request.returnsObjectsAsFaults = true
        request.fetchLimit = 1

        return (try? context.fetch(request))?.first
    }

    static func deduplicatedEntity(with syncable: Syncable, parentUUID: String?, in context: NSManagedObjectContext, using crypter: Crypting) -> BookmarkEntity? {
        if syncable.isDeleted {
            return nil
        }
        let title = try? crypter.base64DecodeAndDecrypt(syncable.encryptedTitle ?? "")
        if syncable.isFolder {
            guard let parentUUID else {
                return nil
            }
            return fetchFolder(withTitle: title, parentUUID: parentUUID, in: context)
        }

        let url = try? crypter.base64DecodeAndDecrypt(syncable.encryptedUrl ?? "")
        return fetchBookmark(withTitle: title, url: url, in: context)
    }

    func update(with syncable: Syncable, in context: NSManagedObjectContext, using crypter: Crypting) throws {
        let payload = syncable.payload
        guard payload["deleted"] == nil else {
            context.delete(self)
            return
        }

        cancelDeletion()
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
