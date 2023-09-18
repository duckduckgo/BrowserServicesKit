//
//  FavoritesDisplayMode.swift
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

import CoreData
import Foundation

public enum FavoritesDisplayMode: Equatable {
    case displayNative(FavoritesFolderID)
    case displayAll(native: FavoritesFolderID)

    public var isDisplayAll: Bool {
        switch self {
        case .displayNative:
            return false
        case .displayAll:
            return true
        }
    }

    public var displayedPlatform: FavoritesFolderID {
        switch self {
        case .displayNative(let platform):
            return platform
        case .displayAll:
            return .unified
        }
    }

    public var nativePlatform: FavoritesFolderID {
        switch self {
        case .displayNative(let native), .displayAll(let native):
            return native
        }
    }

    public var folderUUIDs: Set<String> {
        return [nativePlatform.rawValue, FavoritesFolderID.unified.rawValue]
    }
}

extension BookmarkEntity {

    public func addToFavorites(with displayMode: FavoritesDisplayMode, in context: NSManagedObjectContext) {
        let folders = BookmarkUtils.fetchFavoritesFolders(withUUIDs: displayMode.folderUUIDs, in: context)
        addToFavorites(folders: folders)
    }

    public func removeFromFavorites(with displayMode: FavoritesDisplayMode) {
        let affectedFolders: [BookmarkEntity] = {
            // if displayAll - always remove from all
            // if displayNative:
            //   - if favorited on non-native: only remove from native
            //   - else remove from native and all
            let isFavoritedOnlyOnNativeFormFactor = Set(favoriteFoldersSet.compactMap(\.uuid)) == displayMode.folderUUIDs
            if displayMode.isDisplayAll || isFavoritedOnlyOnNativeFormFactor {
                return Array(favoriteFoldersSet)
            }
            return favoriteFoldersSet.first(where: { $0.uuid == displayMode.nativePlatform.rawValue }).flatMap(Array.init) ?? []
        }()

        removeFromFavorites(folders: affectedFolders)
    }

}
