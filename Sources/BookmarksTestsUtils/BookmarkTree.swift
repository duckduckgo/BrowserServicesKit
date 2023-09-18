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

// swiftlint:disable cyclomatic_complexity function_body_length line_length
public struct ModifiedAtConstraint {
    var check: (Date?) -> Void

    public static func `nil`(file: StaticString = #file, line: UInt = #line) -> ModifiedAtConstraint {
        ModifiedAtConstraint { date in
            XCTAssertNil(date, file: file, line: line)
        }
    }

    public static func notNil(file: StaticString = #file, line: UInt = #line) -> ModifiedAtConstraint {
        ModifiedAtConstraint { date in
            XCTAssertNotNil(date, file: file, line: line)
        }
    }

    public static func greaterThan(_ date: Date, file: StaticString = #file, line: UInt = #line) -> ModifiedAtConstraint {
        ModifiedAtConstraint { actualDate in
            guard let actualDate = actualDate else {
                XCTFail("Date is nil", file: file, line: line)
                return
            }
            XCTAssertGreaterThan(actualDate, date, file: file, line: line)
        }
    }

    public static func lessThan(_ date: Date, file: StaticString = #file, line: UInt = #line) -> ModifiedAtConstraint {
        ModifiedAtConstraint { actualDate in
            guard let actualDate = actualDate else {
                XCTFail("Date is nil", file: file, line: line)
                return
            }
            XCTAssertLessThan(actualDate, date, file: file, line: line)
        }
    }
}

public enum BookmarkTreeNode {
    case bookmark(id: String, name: String?, url: String?, favoritedOn: [FavoritesFolderID], modifiedAt: Date?, isDeleted: Bool, isOrphaned: Bool, modifiedAtConstraint: ModifiedAtConstraint?)
    case folder(id: String, name: String?, children: [BookmarkTreeNode], modifiedAt: Date?, isDeleted: Bool, isOrphaned: Bool, modifiedAtConstraint: ModifiedAtConstraint?)

    public var id: String {
        switch self {
        case .bookmark(let id, _, _, _, _, _, _, _):
            return id
        case .folder(let id, _, _, _, _, _, _):
            return id
        }
    }

    public var name: String? {
        switch self {
        case .bookmark(_, let name, _, _, _, _, _, _):
            return name
        case .folder(_, let name, _, _, _, _, _):
            return name
        }
    }

    public var modifiedAt: Date? {
        switch self {
        case .bookmark(_, _, _, _, let modifiedAt, _, _, _):
            return modifiedAt
        case .folder(_, _, _, let modifiedAt, _, _, _):
            return modifiedAt
        }
    }

    public var isDeleted: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, let isDeleted, _, _):
            return isDeleted
        case .folder(_, _, _, _, let isDeleted, _, _):
            return isDeleted
        }
    }

    public var isOrphaned: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, _, let isOrphaned, _):
            return isOrphaned
        case .folder(_, _, _, _, _, let isOrphaned, _):
            return isOrphaned
        }
    }

    public var modifiedAtConstraint: ModifiedAtConstraint? {
        switch self {
        case .bookmark(_, _, _, _, _, _, _, let modifiedAtConstraint):
            return modifiedAtConstraint
        case .folder(_, _, _, _, _, _, let modifiedAtConstraint):
            return modifiedAtConstraint
        }
    }
}

public protocol BookmarkTreeNodeConvertible {
    func asBookmarkTreeNode() -> BookmarkTreeNode
}

public struct Bookmark: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var url: String?
    var favoritedOn: [FavoritesFolderID]
    var modifiedAt: Date?
    var isDeleted: Bool
    var isOrphaned: Bool
    var modifiedAtConstraint: ModifiedAtConstraint?

    public init(_ name: String? = nil, id: String? = nil, url: String? = nil, favoritedOn: [FavoritesFolderID] = [], modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false, modifiedAtConstraint: ModifiedAtConstraint? = nil) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.url = (url ?? name) ?? id
        self.favoritedOn = favoritedOn
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.modifiedAtConstraint = modifiedAtConstraint
        self.isOrphaned = isOrphaned
    }

    public func asBookmarkTreeNode() -> BookmarkTreeNode {
        .bookmark(id: id, name: name, url: url, favoritedOn: favoritedOn, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned, modifiedAtConstraint: modifiedAtConstraint)
    }
}

public struct Folder: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var modifiedAt: Date?
    var isDeleted: Bool
    var isOrphaned: Bool
    var modifiedAtConstraint: ModifiedAtConstraint?
    var children: [BookmarkTreeNode]

    public init(_ name: String? = nil, id: String? = nil, modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false, @BookmarkTreeBuilder children: () -> [BookmarkTreeNode] = { [] }) {
        self.init(name, id: id, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned, modifiedAtConstraint: nil, children: children)
    }

    public init(_ name: String? = nil, id: String? = nil, modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false, modifiedAtConstraint: ModifiedAtConstraint? = nil, @BookmarkTreeBuilder children: () -> [BookmarkTreeNode] = { [] }) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.isOrphaned = isOrphaned
        self.modifiedAtConstraint = modifiedAtConstraint
        self.children = children()
    }

    public func asBookmarkTreeNode() -> BookmarkTreeNode {
        .folder(id: id, name: name, children: children, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned, modifiedAtConstraint: modifiedAtConstraint)
    }
}

@resultBuilder
public struct BookmarkTreeBuilder {

    public static func buildBlock(_ components: BookmarkTreeNodeConvertible...) -> [BookmarkTreeNode] {
        components.compactMap { $0.asBookmarkTreeNode() }
    }
}

public struct BookmarkTree {

    public init(modifiedAt: Date? = nil, modifiedAtConstraint: ModifiedAtConstraint? = nil, @BookmarkTreeBuilder builder: () -> [BookmarkTreeNode]) {
        self.modifiedAt = modifiedAt
        self.modifiedAtConstraint = modifiedAtConstraint
        self.bookmarkTreeNodes = builder()
    }

    @discardableResult
    public func createEntities(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity]) {
        let (rootFolder, orphans, _) = createEntitiesForCheckingModifiedAt(in: context)
        return (rootFolder, orphans)
    }

    // swiftlint:disable large_tuple
    @discardableResult
    public func createEntitiesForCheckingModifiedAt(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity], [String: ModifiedAtConstraint]) {
        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        rootFolder.modifiedAt = modifiedAt
        let favoritesFolders = FavoritesFolderID.allCases.map { BookmarkUtils.fetchFavoritesFolder(withUUID: $0.rawValue, in: context)! }
        var orphans = [BookmarkEntity]()
        var modifiedAtConstraints = [String: ModifiedAtConstraint]()
        if let modifiedAtConstraint {
            modifiedAtConstraints[BookmarkEntity.Constants.rootFolderID] = modifiedAtConstraint
        }
        for bookmarkTreeNode in bookmarkTreeNodes {
            let (entity, checks) = BookmarkEntity.makeWithModifiedAtConstraints(with: bookmarkTreeNode, rootFolder: rootFolder, favoritesFolders: favoritesFolders, in: context)
            if bookmarkTreeNode.isOrphaned {
                orphans.append(entity)
            }
            modifiedAtConstraints.merge(checks) { (_, rhs) in
                assertionFailure("duplicate keys found")
                return rhs
            }
        }
        return (rootFolder, orphans, modifiedAtConstraints)
    }
    // swiftlint:enable large_tuple

    let modifiedAt: Date?
    let modifiedAtConstraint: ModifiedAtConstraint?
    let bookmarkTreeNodes: [BookmarkTreeNode]
}

public extension BookmarkEntity {
    @discardableResult
    static func make(with treeNode: BookmarkTreeNode, rootFolder: BookmarkEntity, favoritesFolders: [BookmarkEntity], in context: NSManagedObjectContext) -> BookmarkEntity {
        makeWithModifiedAtConstraints(with: treeNode, rootFolder: rootFolder, favoritesFolders: favoritesFolders, in: context).0
    }

    @discardableResult
    static func makeWithModifiedAtConstraints(with treeNode: BookmarkTreeNode, rootFolder: BookmarkEntity, favoritesFolders: [BookmarkEntity], in context: NSManagedObjectContext) -> (BookmarkEntity, [String: ModifiedAtConstraint]) {
        var entity: BookmarkEntity!

        var queues: [[BookmarkTreeNode]] = [[treeNode]]
        var parents: [BookmarkEntity] = [rootFolder]
        var modifiedAtConstraints = [String: ModifiedAtConstraint]()

        while !queues.isEmpty {
            var queue = queues.removeFirst()
            let parent = parents.removeFirst()

            while !queue.isEmpty {
                let node = queue.removeFirst()

                switch node {
                case .bookmark(let id, let name, let url, let favoritedOn, let modifiedAt, let isDeleted, let isOrphaned, let modifiedAtConstraint):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = false
                    bookmarkEntity.title = name
                    bookmarkEntity.url = url
                    bookmarkEntity.modifiedAt = modifiedAt
                    modifiedAtConstraints[id] = modifiedAtConstraint

                    for platform in favoritedOn {
                        if let favoritesFolder = favoritesFolders.first(where: { $0.uuid == platform.rawValue }) {
                            bookmarkEntity.addToFavorites(favoritesRoot: favoritesFolder)
                        }
                    }

                    if isDeleted {
                        bookmarkEntity.markPendingDeletion()
                    }
                    if !isOrphaned {
                        bookmarkEntity.parent = parent
                    }
                case .folder(let id, let name, let children, let modifiedAt, let isDeleted, let isOrphaned, let modifiedAtConstraint):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = true
                    bookmarkEntity.title = name
                    bookmarkEntity.modifiedAt = modifiedAt
                    modifiedAtConstraints[id] = modifiedAtConstraint
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

        return (entity, modifiedAtConstraints)
    }
}

public extension XCTestCase {
    func assertEquivalent(withTimestamps: Bool = true, _ bookmarkEntity: BookmarkEntity, _ tree: BookmarkTree, file: StaticString = #file, line: UInt = #line) {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = bookmarkEntity.managedObjectContext?.persistentStoreCoordinator

        let orphansContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        orphansContext.persistentStoreCoordinator = bookmarkEntity.managedObjectContext?.persistentStoreCoordinator

        var orphans: [BookmarkEntity] = []
        var expectedRootFolder: BookmarkEntity! = nil
        var expectedOrphans: [BookmarkEntity] = []
        var modifiedAtConstraints: [String: ModifiedAtConstraint] = [:]

        orphansContext.performAndWait {
            orphans = BookmarkUtils.fetchOrphanedEntities(orphansContext)
        }

        context.performAndWait {
            context.deleteAll(matching: BookmarkEntity.fetchRequest())
            BookmarkUtils.prepareFoldersStructure(in: context)
            (expectedRootFolder, expectedOrphans, modifiedAtConstraints) = tree.createEntitiesForCheckingModifiedAt(in: context)
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
            XCTAssertEqual(expectedNode.favoritedOn, thisNode.favoritedOn, "favoritedOn mismatch for \(thisUUID)", file: file, line: line)
            if withTimestamps {
                if let modifiedAtConstraint = modifiedAtConstraints[thisUUID] {
                    modifiedAtConstraint.check(thisNode.modifiedAt)
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
// swiftlint:enable cyclomatic_complexity function_body_length line_length
