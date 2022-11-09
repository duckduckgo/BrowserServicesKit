//
//  BookmarkEditorViewModel.swift
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

import Foundation
import Combine

public class BookmarkEditorViewModel: ObservableObject {

    public struct Location {

        public let bookmark: BookmarkEntity?
        public let depth: Int

    }

    let storage: BookmarkListInteracting
    var cancellable: AnyCancellable?

    @Published public var bookmark: BookmarkEntity
    @Published public var locations = [Location]()

    public var canSave: Bool {
        let titleOK = bookmark.title?.trimmingWhitespace().count ?? 0 > 0
        let urlOK = bookmark.isFolder ? true : bookmark.urlObject != nil
        return titleOK && urlOK
    }

    public var canAddNewFolder: Bool {
        !bookmark.isFolder
    }

    public var isNew: Bool

    public init(storage: BookmarkListInteracting, bookmark: BookmarkEntity, isNew: Bool) {
        self.storage = storage
        self.bookmark = bookmark
        self.isNew = isNew

        self.cancellable = self.storage.updates.sink { [weak self] in
            self?.refresh()
        }

        refresh()
    }

    public func refresh() {
        var locations = [Location(bookmark: storage.fetchRootBookmarksFolder(), depth: 0)]

        func descendInto(_ folders: [BookmarkEntity], depth: Int) {
            folders.forEach { entity in
                if entity.isFolder,                    
                    entity.uuid != bookmark.uuid
                {
                    locations.append(Location(bookmark: entity, depth: depth))
                    descendInto(storage.fetchBookmarksInFolder(entity), depth: depth + 1)
                }
            }
        }

        descendInto(storage.fetchBookmarksInFolder(nil), depth: 1)

        self.locations = locations
    }

    public func selectLocationAtIndex(_ index: Int) {
        guard locations.indices.contains(index) else { return }
        guard let newParent = locations[index].bookmark else { return }
        bookmark.parent = newParent
        refresh()
    }

    public func isSelected(_ folder: BookmarkEntity?) -> Bool {
        return bookmark.parent?.uuid == (folder?.uuid ?? BookmarkUtils.Constants.rootFolderID)
    }

}
