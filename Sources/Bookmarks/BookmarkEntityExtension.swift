//
//  BookmarkEntityExtension.swift
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
import CoreData

extension BookmarkEntity {

    #warning("naming?")
    public var urlObject: URL? {
        guard let url = url else { return nil }
        return URL(string: url)
    }

    public static func makeFolder(title: String,
                                  parent: BookmarkEntity,
                                  context: NSManagedObjectContext) -> BookmarkEntity {
        assert(parent.isFolder)
        
        let object = BookmarkEntity(context: context)
        object.uuid = UUID().uuidString
        object.title = title
        object.parent = parent
        object.isFolder = true
        object.isFavorite = false
        return object
    }
    
    public static func makeBookmark(title: String,
                                    url: String,
                                    parent: BookmarkEntity,
                                    context: NSManagedObjectContext) -> BookmarkEntity {
        let object = BookmarkEntity(context: context)
        object.uuid = UUID().uuidString
        object.title = title
        object.url = url
        object.parent = parent
        object.isFolder = false
        object.isFavorite = false
        return object
    }
}
