//
//  BookmarksTreeBuilder.swift
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

enum BookmarkTreeNode {
    case bookmark(id: String, name: String?, url: String?, isDeleted: Bool)
    case folder(id: String, name: String?, children: [BookmarkTreeNode], isDeleted: Bool)

    var id: String {
        switch self {
        case .bookmark(let id, _, _, _):
            return id
        case .folder(let id, _, _, _):
            return id
        }
    }

    var name: String? {
        switch self {
        case .bookmark(_, let name, _, _):
            return name
        case .folder(_, let name, _, _):
            return name
        }
    }

    var isDeleted: Bool {
        switch self {
        case .bookmark(_, _, _, let isDeleted):
            return isDeleted
        case .folder(_, _, _, let isDeleted):
            return isDeleted
        }
    }
}

protocol BookmarkTreeNodeConvertible {
    func asBookmarkTreeNode() -> BookmarkTreeNode
}

struct Bookmark: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var url: String?
    var isDeleted: Bool

    init(_ name: String? = nil, id: String? = nil, url: String? = nil, isDeleted: Bool = false) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.url = url ?? id
        self.isDeleted = isDeleted
    }

    func asBookmarkTreeNode() -> BookmarkTreeNode {
        .bookmark(id: id, name: name, url: url, isDeleted: isDeleted)
    }
}

struct Folder: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var isDeleted: Bool
    var children: [BookmarkTreeNode]

    init(_ name: String?, id: String? = nil, isDeleted: Bool = false, @BookmarkTreeBuilder builder: () -> [BookmarkTreeNode]) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.isDeleted = isDeleted
        self.children = builder()
    }

    func asBookmarkTreeNode() -> BookmarkTreeNode {
        .folder(id: id, name: name, children: children, isDeleted: isDeleted)
    }
}

@resultBuilder
struct BookmarkTreeBuilder {

    static func buildBlock(_ components: BookmarkTreeNodeConvertible...) -> [BookmarkTreeNode] {
        components.compactMap { $0.asBookmarkTreeNode() }
    }
}


struct BookmarksTree {

    init(@BookmarkTreeBuilder builder: () -> [BookmarkTreeNode]) {
        self.bookmarkTreeNodes = builder()
    }

    func createEntities(in context: NSManagedObjectContext) -> BookmarkEntity {
        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        for bookmarkTreeNode in bookmarkTreeNodes {
            BookmarkEntity.make(with: bookmarkTreeNode, rootFolder: rootFolder, in: context)
        }
        return rootFolder
    }

    var bookmarkTreeNodes: [BookmarkTreeNode]
}

extension BookmarkEntity {
    @discardableResult
    static func make(with treeNode: BookmarkTreeNode, rootFolder: BookmarkEntity, in context: NSManagedObjectContext) -> BookmarkEntity {
        var entity: BookmarkEntity!

        var queue: [BookmarkTreeNode] = [treeNode]
        var parents: [BookmarkEntity] = [rootFolder].compactMap { $0 }

        while !queue.isEmpty {
            let node = queue.removeFirst()

            switch node {
            case .bookmark(let id, let name, let url, let isDeleted):
                let bookmarkEntity = BookmarkEntity(context: context)
                if entity == nil {
                    entity = bookmarkEntity
                }
                bookmarkEntity.uuid = id
                bookmarkEntity.parent = parents.last
                bookmarkEntity.title = name
                bookmarkEntity.url = url
                if isDeleted {
                    bookmarkEntity.markPendingDeletion()
                }
                if queue.isEmpty {
                    parents.removeFirst()
                }
            case .folder(let id, let name, let children, let isDeleted):
                let bookmarkEntity = BookmarkEntity(context: context)
                if entity == nil {
                    entity = bookmarkEntity
                }
                bookmarkEntity.uuid = id
                bookmarkEntity.parent = parents.last
                bookmarkEntity.isFolder = true
                bookmarkEntity.title = name
                if isDeleted {
                    bookmarkEntity.markPendingDeletion()
                }
                if queue.isEmpty {
                    parents.removeFirst()
                }
                parents.append(bookmarkEntity)
                queue.append(contentsOf: children)
            }
        }

        return entity
    }
}
