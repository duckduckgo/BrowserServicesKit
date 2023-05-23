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

typealias BookmarkModifiedAtCheck = (Date?) -> Void

enum BookmarkTreeNode {
    case bookmark(id: String, name: String?, url: String?, isFavorite: Bool, modifiedAt: Date?, isDeleted: Bool, isOrphaned: Bool, modifiedAtCheck: BookmarkModifiedAtCheck?)
    case folder(id: String, name: String?, children: [BookmarkTreeNode], modifiedAt: Date?, isDeleted: Bool, isOrphaned: Bool, modifiedAtCheck: BookmarkModifiedAtCheck?)

    var id: String {
        switch self {
        case .bookmark(let id, _, _, _, _, _, _, _):
            return id
        case .folder(let id, _, _, _, _, _, _):
            return id
        }
    }

    var name: String? {
        switch self {
        case .bookmark(_, let name, _, _, _, _, _, _):
            return name
        case .folder(_, let name, _, _, _, _, _):
            return name
        }
    }

    var modifiedAt: Date? {
        switch self {
        case .bookmark(_, _, _, _, let modifiedAt, _, _, _):
            return modifiedAt
        case .folder(_, _, _, let modifiedAt, _, _, _):
            return modifiedAt
        }
    }

    var isDeleted: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, let isDeleted, _, _):
            return isDeleted
        case .folder(_, _, _, _, let isDeleted, _, _):
            return isDeleted
        }
    }

    var isOrphaned: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, _, let isOrphaned, _):
            return isOrphaned
        case .folder(_, _, _, _, _, let isOrphaned, _):
            return isOrphaned
        }
    }

    var modifiedAtCheck: BookmarkModifiedAtCheck? {
        switch self {
        case .bookmark(_, _, _, _, _, _, _, let modifiedAtCheck):
            return modifiedAtCheck
        case .folder(_, _, _, _, _, _, let modifiedAtCheck):
            return modifiedAtCheck
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
    var modifiedAtCheck: BookmarkModifiedAtCheck?

    init(_ name: String? = nil, id: String? = nil, url: String? = nil, isFavorite: Bool = false, modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false, modifiedAtCheck: BookmarkModifiedAtCheck? = nil) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.url = (url ?? name) ?? id
        self.isFavorite = isFavorite
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.modifiedAtCheck = modifiedAtCheck
        self.isOrphaned = isOrphaned
    }

    func asBookmarkTreeNode() -> BookmarkTreeNode {
        .bookmark(id: id, name: name, url: url, isFavorite: isFavorite, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned, modifiedAtCheck: modifiedAtCheck)
    }
}

struct Folder: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var modifiedAt: Date?
    var isDeleted: Bool
    var isOrphaned: Bool
    var modifiedAtCheck: BookmarkModifiedAtCheck?
    var children: [BookmarkTreeNode]

    init(_ name: String? = nil, id: String? = nil, modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false, @BookmarkTreeBuilder children: () -> [BookmarkTreeNode] = { [] }) {
        self.init(name, id: id, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned, modifiedAtCheck: nil, children: children)
    }

    init(_ name: String? = nil, id: String? = nil, modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false, modifiedAtCheck: BookmarkModifiedAtCheck? = nil, @BookmarkTreeBuilder children: () -> [BookmarkTreeNode] = { [] }) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.isOrphaned = isOrphaned
        self.modifiedAtCheck = modifiedAtCheck
        self.children = children()
    }

    func asBookmarkTreeNode() -> BookmarkTreeNode {
        .folder(id: id, name: name, children: children, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned, modifiedAtCheck: modifiedAtCheck)
    }
}

@resultBuilder
struct BookmarkTreeBuilder {

    static func buildBlock(_ components: BookmarkTreeNodeConvertible...) -> [BookmarkTreeNode] {
        components.compactMap { $0.asBookmarkTreeNode() }
    }
}


struct BookmarkTree {

    init(modifiedAt: Date? = nil, modifiedAtCheck: BookmarkModifiedAtCheck? = nil, @BookmarkTreeBuilder builder: () -> [BookmarkTreeNode]) {
        self.modifiedAt = modifiedAt
        self.modifiedAtCheck = modifiedAtCheck
        self.bookmarkTreeNodes = builder()
    }

    @discardableResult
    func createEntities(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity]) {
        let (rootFolder, orphans, _) = createEntitiesForCheckingModifiedAt(in: context)
        return (rootFolder, orphans)
    }

    @discardableResult
    func createEntitiesForCheckingModifiedAt(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity], [String: BookmarkModifiedAtCheck]) {
        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        rootFolder.modifiedAt = modifiedAt
        let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context)!
        var orphans = [BookmarkEntity]()
        var modifiedAtChecks = [String:BookmarkModifiedAtCheck]()
        if let modifiedAtCheck {
            modifiedAtChecks[BookmarkEntity.Constants.rootFolderID] = modifiedAtCheck
        }
        for bookmarkTreeNode in bookmarkTreeNodes {
            let (entity, checks) = BookmarkEntity.makeWithModifiedAtChecks(with: bookmarkTreeNode, rootFolder: rootFolder, favoritesFolder: favoritesFolder, in: context)
            if bookmarkTreeNode.isOrphaned {
                orphans.append(entity)
            }
            modifiedAtChecks.merge(checks) { (lhs, rhs) in
                assertionFailure("duplicate keys found")
                return rhs
            }
        }
        return (rootFolder, orphans, modifiedAtChecks)
    }

    let modifiedAt: Date?
    let modifiedAtCheck: BookmarkModifiedAtCheck?
    let bookmarkTreeNodes: [BookmarkTreeNode]
}

extension BookmarkEntity {
    @discardableResult
    static func make(with treeNode: BookmarkTreeNode, rootFolder: BookmarkEntity, favoritesFolder: BookmarkEntity, in context: NSManagedObjectContext) -> BookmarkEntity {
        makeWithModifiedAtChecks(with: treeNode, rootFolder: rootFolder, favoritesFolder: favoritesFolder, in: context).0
    }

    @discardableResult
    static func makeWithModifiedAtChecks(with treeNode: BookmarkTreeNode, rootFolder: BookmarkEntity, favoritesFolder: BookmarkEntity, in context: NSManagedObjectContext) -> (BookmarkEntity, [String: BookmarkModifiedAtCheck]) {
        var entity: BookmarkEntity!

        var queues: [[BookmarkTreeNode]] = [[treeNode]]
        var parents: [BookmarkEntity] = [rootFolder]
        var modifiedAtChecks = [String:BookmarkModifiedAtCheck]()

        while !queues.isEmpty {
            var queue = queues.removeFirst()
            let parent = parents.removeFirst()

            while !queue.isEmpty {
                let node = queue.removeFirst()

                switch node {
                case .bookmark(let id, let name, let url, let isFavorite, let modifiedAt, let isDeleted, let isOrphaned, let modifiedAtCheck):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = false
                    bookmarkEntity.title = name
                    bookmarkEntity.url = url
                    bookmarkEntity.modifiedAt = modifiedAt
                    modifiedAtChecks[id] = modifiedAtCheck
                    if isFavorite {
                        bookmarkEntity.addToFavorites(favoritesRoot: favoritesFolder)
                    }
                    if isDeleted {
                        bookmarkEntity.markPendingDeletion()
                    }
                    if !isOrphaned {
                        bookmarkEntity.parent = parent
                    }
                case .folder(let id, let name, let children, let modifiedAt, let isDeleted, let isOrphaned, let modifiedAtCheck):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = true
                    bookmarkEntity.title = name
                    bookmarkEntity.modifiedAt = modifiedAt
                    modifiedAtChecks[id] = modifiedAtCheck
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

        return (entity, modifiedAtChecks)
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
        var modifiedAtChecks: [String: BookmarkModifiedAtCheck] = [:]

        orphansContext.performAndWait {
            orphans = BookmarkUtils.fetchOrphanedEntities(orphansContext)
        }

        context.performAndWait {
            context.deleteAll(matching: BookmarkEntity.fetchRequest())
            BookmarkUtils.prepareFoldersStructure(in: context)
            (expectedRootFolder, expectedOrphans, modifiedAtChecks) = tree.createEntitiesForCheckingModifiedAt(in: context)
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
                if let modifiedAtCheck = modifiedAtChecks[thisUUID] {
                    modifiedAtCheck(thisNode.modifiedAt)
                } else {
                    XCTAssertEqual(expectedNode.modifiedAt, thisNode.modifiedAt, "modifiedAt mismatch for \(thisUUID)", file: file, line: line)
                }
            }

            if expectedNode.isFolder {
                XCTAssertEqual(expectedNode.childrenArray.count, thisNode.childrenArray.count, "children count mismatch for \(thisUUID)", file: file, line: line)
                expectedTreeQueue.append(contentsOf: expectedNode.childrenArray)
                thisTreeQueue.append(contentsOf: thisNode.childrenArray)
            }
        }
    }
}
