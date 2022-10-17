//
//  File.swift
//  
//
//  Created by Bartek on 17/10/2022.
//

import Foundation

extension BookmarkEntity {
    public typealias ListOrderAccessors = (next: WritableKeyPath<BookmarkEntity, BookmarkEntity?>,
                                           previous: WritableKeyPath<BookmarkEntity, BookmarkEntity?>)
    
    public static var bookmarkOrdering: ListOrderAccessors {
        (\.next, \.previous)
    }
    
    public static var favoritesOrdering: ListOrderAccessors {
        (\.nextFavorite, \.previousFavorite)
    }
}

public enum ArrayExtension: Error {
    case indexOutOfBounds
}

extension Array where Element: BookmarkEntity {

    public func movingBookmark(fromIndex: Int,
                               toIndex: Int,
                               orderAccessors: BookmarkEntity.ListOrderAccessors) throws -> [BookmarkEntity] {
        guard fromIndex < count, toIndex < count else {
            throw ArrayExtension.indexOutOfBounds
        }
        
        var result = self
        let element = result.remove(at: fromIndex)
        result.insert(element, at: toIndex)
        
        var bookmark = element as BookmarkEntity
        // Remove from list
        if var preceding = bookmark[keyPath: orderAccessors.previous] {
            preceding[keyPath: orderAccessors.next] = bookmark[keyPath: orderAccessors.next]
        } else if var following = bookmark[keyPath: orderAccessors.next] {
            following[keyPath: orderAccessors.previous] = bookmark[keyPath: orderAccessors.previous]
        }
        
        // Insert in new place
        let newPreceding: BookmarkEntity? = toIndex > 0 ? result[toIndex - 1] : nil
        let newFollowing: BookmarkEntity? = toIndex + 1 < result.count ? result[toIndex + 1] : nil
        
        bookmark[keyPath: orderAccessors.previous] = newPreceding
        bookmark[keyPath: orderAccessors.next] = newFollowing
        
        return result
    }
    
}
