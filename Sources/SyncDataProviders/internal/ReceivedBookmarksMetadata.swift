//
//  ReceivedBookmarksMetadata.swift
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
import DDGSync
import Foundation

struct ReceivedBookmarksMetadata {
    let received: [Syncable]
    let receivedIDs: Set<String>
    let parentFoldersToChildrenMap: [String: String]
    let childrenToParentFoldersMap: [String: [String]]

    init(received: [Syncable]) {
        self.received = received
        (receivedIDs, parentFoldersToChildrenMap, childrenToParentFoldersMap) = received.indexIDs()
    }
}

extension Array where Element == Syncable {

    func indexIDs() -> (allIDs: Set<String>, parentFoldersToChildren: [String: String], childrenToParents: [String: [String]]) {
        var childrenToParents: [String: String] = [:]
        var parentFoldersToChildren: [String: [String]] = [:]

        let allIDs: Set<String> = reduce(into: .init()) { partialResult, syncable in
            if let uuid = syncable.id {
                partialResult.insert(uuid)
                if syncable.isFolder {
                    partialResult.formUnion(syncable.children)
                }

                if uuid != BookmarkEntity.Constants.favoritesFolderID {
                    if syncable.isFolder {
                        parentFoldersToChildren[uuid] = syncable.children
                    }
                    syncable.children.forEach { child in
                        childrenToParents[child] = uuid
                    }
                }
            }
        }

        return (allIDs, childrenToParents, parentFoldersToChildren)
    }
}
