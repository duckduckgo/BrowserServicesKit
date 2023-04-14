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

    public init(bookmarkDatabase: CoreDataDatabase, saveErrorHandler: @escaping (Error) -> Void) {
        self.database = bookmarkDatabase
        self.saveErrorHandler = saveErrorHandler

        cleanupCancellable = triggerSubject
            .receive(on: workQueue)
            .sink { [weak self] _ in
                self?.removeBookmarksPendingDeletion()
            }
    }

    public func scheduleRegularCleaning() {
        scheduleCleanupCancellable?.cancel()
        scheduleCleanupCancellable = Timer.publish(every: Const.cleanupInterval, on: .main, in: .default)
            .sink { [weak self] _ in
                self?.triggerSubject.send()
            }
    }

    public func cleanUpDatabaseNow() {
        triggerSubject.send()
    }

    private func removeBookmarksPendingDeletion() {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            let bookmarksPendingDeletion = BookmarkUtils.fetchBookmarksPendingDeletion(context)

            for bookmark in bookmarksPendingDeletion {
                context.delete(bookmark)
            }

            do {
                try context.save()
            } catch {
                saveErrorHandler(error)
            }
        }
    }

    private enum Const {
        static let cleanupInterval: TimeInterval = 24 * 3600
    }

    private let saveErrorHandler: (Error) -> Void

    private let database: CoreDataDatabase
    private let triggerSubject = PassthroughSubject<Void, Never>()
    private let workQueue = DispatchQueue(label: "BookmarkDatabaseCleaner queue", qos: .userInitiated)

    private var cleanupCancellable: AnyCancellable?
    private var scheduleCleanupCancellable: AnyCancellable?
}
