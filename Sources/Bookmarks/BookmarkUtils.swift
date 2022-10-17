//
//
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation

extension BookmarkEntity {
    public struct LinkedListAccessors {
        public let next: WritableKeyPath<BookmarkEntity, BookmarkEntity?>
        public let previous: WritableKeyPath<BookmarkEntity, BookmarkEntity?>
        
        private init(next: WritableKeyPath<BookmarkEntity, BookmarkEntity?>,
                     previous: WritableKeyPath<BookmarkEntity, BookmarkEntity?>) {
            self.next = next
            self.previous = previous
        }
        
        public static let bookmarkAccessors = LinkedListAccessors(next: \.next, previous: \.previous)
        public static let favoritesAccessors = LinkedListAccessors(next: \.nextFavorite, previous: \.previousFavorite)
    }

}

public enum ArrayExtension: Error {
    case indexOutOfBounds
}

extension Array where Element: BookmarkEntity {
    
    public func sortedBookmarkEntities(using accessors: BookmarkEntity.LinkedListAccessors) -> [BookmarkEntity] {
        guard let first = self.first(where: { $0[keyPath: accessors.previous] == nil }) else {
            // TODO: pixel
            return self
        }
        
        var sorted: [BookmarkEntity] = [first]
        sorted.reserveCapacity(count)
        
        var current = first[keyPath: accessors.next]
        while let next = current {
            sorted.append(next)
            current = next[keyPath: accessors.next]
        }
        
        return sorted
    }

    public func movingBookmarkEntity(fromIndex: Int,
                                     toIndex: Int,
                                     using accessors: BookmarkEntity.LinkedListAccessors) throws -> [BookmarkEntity] {
        guard fromIndex < count, toIndex < count else {
            throw ArrayExtension.indexOutOfBounds
        }
        
        var result = self
        let element = result.remove(at: fromIndex)
        result.insert(element, at: toIndex)
        
        var bookmark = element as BookmarkEntity
        // Remove from list
        if var preceding = bookmark[keyPath: accessors.previous] {
            preceding[keyPath: accessors.next] = bookmark[keyPath: accessors.next]
        } else if var following = bookmark[keyPath: accessors.next] {
            following[keyPath: accessors.previous] = bookmark[keyPath: accessors.previous]
        }
        
        // Insert in new place
        let newPreceding: BookmarkEntity? = toIndex > 0 ? result[toIndex - 1] : nil
        let newFollowing: BookmarkEntity? = toIndex + 1 < result.count ? result[toIndex + 1] : nil
        
        bookmark[keyPath: accessors.previous] = newPreceding
        bookmark[keyPath: accessors.next] = newFollowing
        
        return result
    }
    
}
