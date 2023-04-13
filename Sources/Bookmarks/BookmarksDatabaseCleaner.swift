//
//  BookmarkDatabaseCleaner.swift
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

import Foundation
import CoreData
import Persistence
import Combine

public final class BookmarkDatabaseCleaner {

    public init(bookmarkDatabase: CoreDataDatabase) {
        self.context = bookmarkDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
    }

    public func removeBookmarksPendingDeletion() async throws {

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.performAndWait {
                do {
                    let bookmarksPendingDeletion = BookmarkUtils.fetchBookmarksPendingDeletion(self.context)

                    for bookmark in bookmarksPendingDeletion {
                        context.delete(bookmark)
                    }

                    try context.save()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private let context: NSManagedObjectContext
}
