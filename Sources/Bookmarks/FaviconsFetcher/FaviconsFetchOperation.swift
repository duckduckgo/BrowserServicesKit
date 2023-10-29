//
//  FaviconsFetchOperation.swift
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
import Combine
import Common
import CoreData
import Persistence

class FaviconsFetchOperation: Operation {

   var didStart: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didStart
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didStart = newValue
        }
    }

    var didFinish: ((Error?) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didFinish
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didFinish = newValue
        }
    }

    init(
        database: CoreDataDatabase,
        metadataStore: BookmarkFaviconsMetadataStoring,
        fetcher: FaviconFetching,
        faviconStore: FaviconStoring,
        modifiedBookmarkIDs: Set<String>,
        deletedBookmarkIDs: Set<String>,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.database = database
        self.metadataStore = metadataStore
        self.fetcher = fetcher
        self.faviconStore = faviconStore
        self.modifiedBookmarkIDs = modifiedBookmarkIDs
        self.deletedBookmarkIDs = deletedBookmarkIDs
        self.getLog = log
    }

    override func start() {
        guard !isCancelled else {
            isExecuting = false
            isFinished = true
            return
        }

        isExecuting = true
        isFinished = false

        didStart?()

        Task {
            defer {
                isExecuting = false
                isFinished = true
            }

            do {
                try await fetchFavicons()
                didFinish?(nil)
            } catch is CancellationError {
                didFinish?(nil)
            } catch {
                didFinish?(error)
            }
        }
    }

    func fetchFavicons() async throws {
        os_log(.debug, log: log, "Favicons Fetch Operation Started")
        defer {
            os_log(.debug, log: log, "Favicons Fetch Operation Finished")
        }

        var ids = try metadataStore.getBookmarkIDs().union(modifiedBookmarkIDs).subtracting(deletedBookmarkIDs)
        var urlsByID = [String:URL]()
        var idsWithoutFavicons = Set<String>()

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            let bookmarks = fetchBookmarks(with: ids, in: context)
            ids.removeAll()
            bookmarks.forEach { bookmark in
                if let uuid = bookmark.uuid, let urlString = bookmark.url, let url = URL(string: urlString) {
                    urlsByID[uuid] = url
                    ids.insert(uuid)
                }
            }
        }

        try checkCancellation()
        try metadataStore.storeBookmarkIDs(ids)

        var idsArray = Array(ids)

        while !idsArray.isEmpty {
            print("IDS ARRAY SIZE: \(idsArray.count)")
            let numberOfIdsToFetch = min(10, idsArray.count)
            let idsToFetch = Array(idsArray.prefix(upTo: numberOfIdsToFetch))
            idsArray = Array(idsArray.dropFirst(numberOfIdsToFetch))

            let newIdsWithoutFavicons = try await withThrowingTaskGroup(of: String?.self, returning: Set<String>.self) { group in
                for id in idsToFetch {
                    if let url = urlsByID[id] {
                        group.addTask { [weak self] in
                            guard let self else {
                                return nil
                            }
                            do {
                                if let image = try await self.fetcher.fetchFavicon(for: url) {
                                    os_log(.debug, log: self.log, "Favicon found for %{public}s", url.absoluteString)
                                    try await self.faviconStore.storeFavicon(image, for: url)
                                    try checkCancellation()
                                    return nil
                                } else {
                                    os_log(.debug, log: self.log, "Favicon not found for %{public}s", url.absoluteString)
                                    try checkCancellation()
                                    return id
                                }
                            } catch {
                                os_log(.debug, log: self.log, "Error fetching favicon for %{public}s: %{public}s", url.absoluteString, error.localizedDescription)
                                try checkCancellation()
                                return nil
                            }
                        }
                    }
                }

                try checkCancellation()

                var results = Set<String>()
                for try await value in group {
                    if let value {
                        results.insert(value)
                    }
                }
                return results
            }

            try checkCancellation()

            idsWithoutFavicons.formUnion(newIdsWithoutFavicons)
        }
    }


    private func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }

    private func fetchBookmarks(with uuids: any Sequence & CVarArg, in context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@ AND %K == NO", #keyPath(BookmarkEntity.uuid), uuids, #keyPath(BookmarkEntity.isFolder))
        request.propertiesToFetch = [#keyPath(BookmarkEntity.url)]

        return (try? context.fetch(request)) ?? []
    }

    private var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog

    // MARK: - Overrides

    override var isAsynchronous: Bool { true }

    override var isExecuting: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isExecuting
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isExecuting))
            _isExecuting = newValue
            didChangeValue(forKey: #keyPath(isExecuting))
        }
    }

    override var isFinished: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isFinished
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isFinished))
            _isFinished = newValue
            didChangeValue(forKey: #keyPath(isFinished))
        }
    }

    private let modifiedBookmarkIDs: Set<String>
    private let deletedBookmarkIDs: Set<String>
    private let lock = NSRecursiveLock()

    private let database: CoreDataDatabase
    private let metadataStore: BookmarkFaviconsMetadataStoring
    private let fetcher: FaviconFetching
    private let faviconStore: FaviconStoring

    private var _isExecuting: Bool = false
    private var _isFinished: Bool = false
    private var _didStart: (() -> Void)?
    private var _didFinish: ((Error?) -> Void)?
    private var _didReceiveHTTPRequestError: ((Error) -> Void)?
}
