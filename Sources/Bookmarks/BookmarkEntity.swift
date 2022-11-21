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
        public static let rootFolderID = "root_folder"
        public static let favoritesFolderID = "favorites_folder"
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BookmarkEntity> {
        return NSFetchRequest<BookmarkEntity>(entityName: "BookmarkEntity")
    }

    @NSManaged public fileprivate(set) var isFavorite: Bool
    @NSManaged public var isFolder: Bool
    @NSManaged public var title: String?
    @NSManaged public var url: String?
    @NSManaged public var uuid: String?
    @NSManaged public var children: NSOrderedSet?
    @NSManaged fileprivate(set) var favoriteFolder: BookmarkEntity?
    @NSManaged public fileprivate(set) var favorites: NSOrderedSet?
    @NSManaged public var parent: BookmarkEntity?
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        uuid = UUID().uuidString
        isFavorite = false
    }
    
    public var urlObject: URL? {
        guard let url = url else { return nil }
        return URL(string: url)
    }
    
    public var isRoot: Bool {
        uuid == Constants.rootFolderID
    }
    
    public var childrenArray: [BookmarkEntity] {
        children?.array as? [BookmarkEntity] ?? []
    }

    public static func makeFolder(title: String,
                                  parent: BookmarkEntity,
                                  context: NSManagedObjectContext) -> BookmarkEntity {
        assert(parent.isFolder)
        let object = BookmarkEntity(context: context)
        object.title = title
        object.parent = parent
        object.isFolder = true
        return object
    }
    
    public static func makeBookmark(title: String,
                                    url: String,
                                    parent: BookmarkEntity,
                                    context: NSManagedObjectContext) -> BookmarkEntity {
        let object = BookmarkEntity(context: context)
        object.title = title
        object.url = url
        object.parent = parent
        object.isFolder = false
        return object
    }
    
    public func addToFavorites(favoritesRoot root: BookmarkEntity) {
        assert(root.uuid == BookmarkEntity.Constants.favoritesFolderID)
        
        isFavorite = true
        root.addToFavorites(self)
    }
    
    public func removeFromFavorites() {
        isFavorite = false
        favoriteFolder = nil
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

    @objc(addFavoritesObject:)
    @NSManaged private func addToFavorites(_ value: BookmarkEntity)

    @objc(removeFavoritesObject:)
    @NSManaged private func removeFromFavorites(_ value: BookmarkEntity)

    @objc(addFavorites:)
    @NSManaged private func addToFavorites(_ values: NSOrderedSet)

    @objc(removeFavorites:)
    @NSManaged private func removeFromFavorites(_ values: NSOrderedSet)
    
}

extension BookmarkEntity : Identifiable {

}

