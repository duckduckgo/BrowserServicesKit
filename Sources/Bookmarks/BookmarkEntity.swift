//
//  BookmarkEntity.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
//

import Foundation
import CoreData

@objc(BookmarkEntity)
public class BookmarkEntity: NSManagedObject {
    
    public enum Constants {
        public static let rootFolderID = "bookmarks_root"
        public static let favoritesFolderID = "favorites_root"
    }

    public enum Error: Swift.Error {
        case folderStructureHasCycle
        case folderHasURL
        case invalidFavoritesFolder
        case invalidFavoritesStatus
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BookmarkEntity> {
        return NSFetchRequest<BookmarkEntity>(entityName: "BookmarkEntity")
    }
    
    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "BookmarkEntity", in: context)!
    }

    @NSManaged public var isFolder: Bool
    @NSManaged public var title: String?
    @NSManaged public var url: String?
    @NSManaged public var uuid: String?
    @NSManaged public var children: NSOrderedSet?
    @NSManaged fileprivate(set) public var favoriteFolder: BookmarkEntity?
    @NSManaged public fileprivate(set) var favorites: NSOrderedSet?
    @NSManaged public var parent: BookmarkEntity?

    @NSManaged public fileprivate(set) var isPendingDeletion: Bool
    @NSManaged public var modifiedAt: Date?
    /// In-memory flag. When set to `false`, disables adjusting `modifiedAt` on `willSave()`. It's reset to `true` on `didSave()`.
    public var shouldManageModifiedAt: Bool = true

    public var isFavorite: Bool {
        favoriteFolder != nil
    }

    public convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: BookmarkEntity.entity(in: moc),
                  insertInto: moc)
    }
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        uuid = UUID().uuidString
    }

    public override func willSave() {
        guard shouldManageModifiedAt else {
            return
        }
        let changedKeys = changedValues().keys
        guard !changedKeys.isEmpty, !changedKeys.contains(NSStringFromSelector(#selector(getter: modifiedAt))) else {
            return
        }
        if isInserted && (uuid == Constants.rootFolderID || uuid == Constants.favoritesFolderID) {
            return
        }
        modifiedAt = Date()
        if changedKeys.contains(NSStringFromSelector(#selector(getter: isPendingDeletion))) && isPendingDeletion {
            parent?.modifiedAt = modifiedAt
        }
    }

    public override func didSave() {
        shouldManageModifiedAt = true
    }

    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validate()
    }

    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validate()
    }
    
    public var urlObject: URL? {
        guard let url = url else { return nil }
        return url.isBookmarklet() ? url.toEncodedBookmarklet() : URL(string: url)
    }
    
    public var isRoot: Bool {
        uuid == Constants.rootFolderID
    }
    
    public var childrenArray: [BookmarkEntity] {
        let children = children?.array as? [BookmarkEntity] ?? []
        return children.filter { $0.isPendingDeletion == false }
    }

    public var favoritesArray: [BookmarkEntity] {
        let children = favorites?.array as? [BookmarkEntity] ?? []
        return children.filter { $0.isPendingDeletion == false }
    }

    public static func makeFolder(title: String,
                                  parent: BookmarkEntity,
                                  insertAtBeginning: Bool = false,
                                  context: NSManagedObjectContext) -> BookmarkEntity {
        assert(parent.isFolder)
        let object = BookmarkEntity(context: context)
        object.title = title
        object.isFolder = true
        
        if insertAtBeginning {
            parent.insertIntoChildren(object, at: 0)
        } else {
            parent.addToChildren(object)
        }
        return object
    }
    
    public static func makeBookmark(title: String,
                                    url: String,
                                    parent: BookmarkEntity,
                                    insertAtBeginning: Bool = false,
                                    context: NSManagedObjectContext) -> BookmarkEntity {
        let object = BookmarkEntity(context: context)
        object.title = title
        object.url = url
        object.isFolder = false
        
        if insertAtBeginning {
            parent.insertIntoChildren(object, at: 0)
        } else {
            parent.addToChildren(object)
        }
        return object
    }
    
    // If `insertAt` is nil, it is inserted at the end.
    public func addToFavorites(insertAt: Int? = nil,
                               favoritesRoot root: BookmarkEntity) {

        if let position = insertAt {
            root.insertIntoFavorites(self, at: position)
        } else {
            root.addToFavorites(self)
        }
    }
    
    public func removeFromFavorites() {
        favoriteFolder = nil
    }

    public func markPendingDeletion() {
        var queue: [BookmarkEntity] = [self]

        while !queue.isEmpty {
            let currentObject = queue.removeFirst()

            currentObject.url = nil
            currentObject.title = nil
            currentObject.isPendingDeletion = true

            if currentObject.isFolder {
                queue.append(contentsOf: currentObject.childrenArray)
            }
        }
    }

    public func cancelDeletion() {
        isPendingDeletion = false
    }
}

// MARK: Validation
extension BookmarkEntity {

    func validate() throws {
        try validateThatFoldersDoNotHaveURLs()
        try validateThatFolderHierarchyHasNoCycles()
        try validateFavoritesStatus()
        try validateFavoritesFolder()
    }

    func validateFavoritesStatus() throws {
        let isInFavoriteCollection = favoriteFolder != nil
        if isFavorite != isInFavoriteCollection {
            throw Error.invalidFavoritesStatus
        }
    }

    func validateFavoritesFolder() throws {
        if let favoritesFolderID = favoriteFolder?.uuid,
            favoritesFolderID != Constants.favoritesFolderID {
            throw Error.invalidFavoritesFolder
        }
    }

    func validateThatFoldersDoNotHaveURLs() throws {
        if isFolder, url != nil {
            throw Error.folderHasURL
        }
    }

    /// Validates that entities do not reference any of their ancestors, causing a cycle.
    /// We don't need to look at children, as due to relationships nature, any relationship change affects at least two Entities - thus it is ok to validate only by checking towards Root.
    func validateThatFolderHierarchyHasNoCycles() throws {

        var currentFolder: BookmarkEntity? = self

        while let current = currentFolder {
            if current.parent?.uuid == uuid {
                throw Error.folderStructureHasCycle
            }

            currentFolder = currentFolder?.parent
        }
    }

}

// MARK: Generated accessors for children
extension BookmarkEntity {

    @objc(insertObject:inChildrenAtIndex:)
    @NSManaged public func insertIntoChildren(_ value: BookmarkEntity, at idx: Int)

    @objc(removeObjectFromChildrenAtIndex:)
    @NSManaged public func removeFromChildren(at idx: Int)

    @objc(insertChildren:atIndexes:)
    @NSManaged public func insertIntoChildren(_ values: [BookmarkEntity], at indexes: NSIndexSet)

    @objc(removeChildrenAtIndexes:)
    @NSManaged public func removeFromChildren(at indexes: NSIndexSet)

    @objc(replaceObjectInChildrenAtIndex:withObject:)
    @NSManaged public func replaceChildren(at idx: Int, with value: BookmarkEntity)

    @objc(replaceChildrenAtIndexes:withChildren:)
    @NSManaged public func replaceChildren(at indexes: NSIndexSet, with values: [BookmarkEntity])

    @objc(addChildrenObject:)
    @NSManaged public func addToChildren(_ value: BookmarkEntity)

    @objc(removeChildrenObject:)
    @NSManaged public func removeFromChildren(_ value: BookmarkEntity)

    @objc(addChildren:)
    @NSManaged public func addToChildren(_ values: NSOrderedSet)

    @objc(removeChildren:)
    @NSManaged public func removeFromChildren(_ values: NSOrderedSet)

}

// MARK: Generated accessors for favorites
extension BookmarkEntity {
    
    @objc(insertObject:inFavoritesAtIndex:)
    @NSManaged private func insertIntoFavorites(_ value: BookmarkEntity, at idx: Int)

    @objc(addFavoritesObject:)
    @NSManaged private func addToFavorites(_ value: BookmarkEntity)

    @objc(removeFavoritesObject:)
    @NSManaged private func removeFromFavorites(_ value: BookmarkEntity)

    @objc(addFavorites:)
    @NSManaged private func addToFavorites(_ values: NSOrderedSet)

    @objc(removeFavorites:)
    @NSManaged private func removeFromFavorites(_ values: NSOrderedSet)
    
}

extension BookmarkEntity: Identifiable {

}
