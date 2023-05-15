//
//  BookmarkTree.swift
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
import Foundation
import XCTest

enum BookmarkTreeNode {
    case bookmark(id: String, name: String?, url: String?, isFavorite: Bool, modifiedAt: Date?, isDeleted: Bool, isOrphaned: Bool)
    case folder(id: String, name: String?, children: [BookmarkTreeNode], modifiedAt: Date?, isDeleted: Bool, isOrphaned: Bool)

    var id: String {
        switch self {
        case .bookmark(let id, _, _, _, _, _, _):
            return id
        case .folder(let id, _, _, _, _, _):
            return id
        }
    }

    var name: String? {
        switch self {
        case .bookmark(_, let name, _, _, _, _, _):
            return name
        case .folder(_, let name, _, _, _, _):
            return name
        }
    }

    var modifiedAt: Date? {
        switch self {
        case .bookmark(_, _, _, _, let modifiedAt, _, _):
            return modifiedAt
        case .folder(_, _, _, let modifiedAt, _, _):
            return modifiedAt
        }
    }

    var isDeleted: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, let isDeleted, _):
            return isDeleted
        case .folder(_, _, _, _, let isDeleted, _):
            return isDeleted
        }
    }

    var isOrphaned: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, _, let isOrphaned):
            return isOrphaned
        case .folder(_, _, _, _, _, let isOrphaned):
            return isOrphaned
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
    var isFavorite: Bool
    var modifiedAt: Date?
    var isDeleted: Bool
    var isOrphaned: Bool

    init(_ name: String? = nil, id: String? = nil, url: String? = nil, isFavorite: Bool = false, modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.url = (url ?? name) ?? id
        self.isFavorite = isFavorite
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.isOrphaned = isOrphaned
    }

    func asBookmarkTreeNode() -> BookmarkTreeNode {
        .bookmark(id: id, name: name, url: url, isFavorite: isFavorite, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned)
    }
}

struct Folder: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var modifiedAt: Date?
    var isDeleted: Bool
    var isOrphaned: Bool
    var children: [BookmarkTreeNode]

    init(_ name: String? = nil, id: String? = nil, modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false, @BookmarkTreeBuilder builder: () -> [BookmarkTreeNode] = { [] }) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.isOrphaned = isOrphaned
        self.children = builder()
    }

    func asBookmarkTreeNode() -> BookmarkTreeNode {
        .folder(id: id, name: name, children: children, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned)
    }
}

@resultBuilder
struct BookmarkTreeBuilder {

    static func buildBlock(_ components: BookmarkTreeNodeConvertible...) -> [BookmarkTreeNode] {
        components.compactMap { $0.asBookmarkTreeNode() }
    }
}


struct BookmarkTree {

    init(@BookmarkTreeBuilder builder: () -> [BookmarkTreeNode]) {
        self.bookmarkTreeNodes = builder()
    }

    @discardableResult
    func createEntities(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity]) {
        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context)!
        var orphans = [BookmarkEntity]()
        for bookmarkTreeNode in bookmarkTreeNodes {
            let entity = BookmarkEntity.make(with: bookmarkTreeNode, rootFolder: rootFolder, favoritesFolder: favoritesFolder, in: context)
            if bookmarkTreeNode.isOrphaned {
                orphans.append(entity)
            }
        }
        return (rootFolder, orphans)
    }

    var bookmarkTreeNodes: [BookmarkTreeNode]
}

extension BookmarkEntity {
    @discardableResult
    static func make(with treeNode: BookmarkTreeNode, rootFolder: BookmarkEntity, favoritesFolder: BookmarkEntity, in context: NSManagedObjectContext) -> BookmarkEntity {
        var entity: BookmarkEntity!

        var queues: [[BookmarkTreeNode]] = [[treeNode]]
        var parents: [BookmarkEntity] = [rootFolder]

        while !queues.isEmpty {
            var queue = queues.removeFirst()
            let parent = parents.removeFirst()

            while !queue.isEmpty {
                let node = queue.removeFirst()

                switch node {
                case .bookmark(let id, let name, let url, let isFavorite, let modifiedAt, let isDeleted, let isOrphaned):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = false
                    bookmarkEntity.title = name
                    bookmarkEntity.url = url
                    bookmarkEntity.modifiedAt = modifiedAt
                    if isFavorite {
                        bookmarkEntity.addToFavorites(favoritesRoot: favoritesFolder)
                    }
                    if isDeleted {
                        bookmarkEntity.markPendingDeletion()
                    }
                    if !isOrphaned {
                        bookmarkEntity.parent = parent
                    }
                case .folder(let id, let name, let children, let modifiedAt, let isDeleted, let isOrphaned):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = true
                    bookmarkEntity.title = name
                    bookmarkEntity.modifiedAt = modifiedAt
                    if isDeleted {
                        bookmarkEntity.markPendingDeletion()
                    }
                    if !isOrphaned {
                        bookmarkEntity.parent = parent
                    }
                    parents.append(bookmarkEntity)
                    queues.append(children)
                }
            }
        }

        return entity
    }
}


extension XCTestCase {
    func assertEquivalent(withTimestamps: Bool = true, _ bookmarkEntity: BookmarkEntity, _ tree: BookmarkTree, file: StaticString = #file, line: UInt = #line) {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = bookmarkEntity.managedObjectContext?.persistentStoreCoordinator

        let orphansContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        orphansContext.persistentStoreCoordinator = bookmarkEntity.managedObjectContext?.persistentStoreCoordinator

        var orphans: [BookmarkEntity] = []
        var expectedRootFolder: BookmarkEntity! = nil
        var expectedOrphans: [BookmarkEntity] = []

        orphansContext.performAndWait {
            orphans = BookmarkUtils.fetchOrphanedEntities(orphansContext)
        }

        context.performAndWait {
            context.deleteAll(matching: BookmarkEntity.fetchRequest())
            BookmarkUtils.prepareFoldersStructure(in: context)
            (expectedRootFolder, expectedOrphans) = tree.createEntities(in: context)
        }

        let thisFolder = bookmarkEntity
        XCTAssertEqual(expectedRootFolder.uuid, thisFolder.uuid, "root folder uuid mismatch", file: file, line: line)

        var expectedTreeQueue: [BookmarkEntity] = [[expectedRootFolder], expectedOrphans].flatMap { $0 }
        var thisTreeQueue: [BookmarkEntity] = [[thisFolder], orphans].flatMap { $0 }

        while !expectedTreeQueue.isEmpty {
            guard !thisTreeQueue.isEmpty else {
                XCTFail("No more children in the tree, while \(expectedTreeQueue.count) (ids: \(expectedTreeQueue.compactMap(\.uuid))) still expected", file: file, line: line)
                return
            }
            let expectedNode = expectedTreeQueue.removeFirst()
            let thisNode = thisTreeQueue.removeFirst()

            let thisUUID = thisNode.uuid ?? "<no local UUID>"

            XCTAssertEqual(expectedNode.uuid, thisNode.uuid, "uuid mismatch", file: file, line: line)
            XCTAssertEqual(expectedNode.title, thisNode.title, "title mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.url, thisNode.url, "url mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.isFolder, thisNode.isFolder, "isFolder mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.isPendingDeletion, thisNode.isPendingDeletion, "isPendingDeletion mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.children?.count, thisNode.children?.count, "children count mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.isFavorite, thisNode.isFavorite, "isFavorite mismatch for \(thisUUID)", file: file, line: line)
            if withTimestamps {
                XCTAssertEqual(expectedNode.modifiedAt, thisNode.modifiedAt, "modifiedAt mismatch for \(thisUUID)", file: file, line: line)
            }

            if expectedNode.isFolder {
                XCTAssertEqual(expectedNode.childrenArray.count, thisNode.childrenArray.count, "children count mismatch for \(thisUUID)", file: file, line: line)
                expectedTreeQueue.append(contentsOf: expectedNode.childrenArray)
                thisTreeQueue.append(contentsOf: thisNode.childrenArray)
            }
        }
    }
}
