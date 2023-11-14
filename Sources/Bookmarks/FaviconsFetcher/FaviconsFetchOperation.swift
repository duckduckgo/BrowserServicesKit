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
        stateStore: BookmarksFaviconsFetcherStateStoring,
        fetcher: FaviconFetching,
        faviconStore: FaviconStoring,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.database = database
        self.stateStore = stateStore
        self.fetcher = fetcher
        self.faviconStore = faviconStore
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
        var ids = try stateStore.getBookmarkIDs()

        guard !ids.isEmpty else {
            os_log(.debug, log: log, "No new Favicons to fetch")
            return
        }

        os_log(.debug, log: log, "Favicons Fetch Operation started")
        defer {
            os_log(.debug, log: log, "Favicons Fetch Operation finished")
        }

        let idsByDomain = mapBookmarkDomainsToUUIDs(for: ids).filter { [weak self] (domain, _) in
            self?.faviconStore.hasFavicon(for: domain) == false
        }
        ids = Set(idsByDomain.values.flatMap { $0 })

        try checkCancellation()

        let domains = Set(idsByDomain.keys)
        var domainsArray = Array(domains)

        guard !domainsArray.isEmpty else {
            os_log(.debug, log: log, "No favicons to fetch")
            try stateStore.storeBookmarkIDs(ids)
            return
        }
        os_log(.debug, log: log, "Will try to fetch favicons for %{public}d domains", domainsArray.count)

        while !domainsArray.isEmpty {
            let numberOfDomainsToFetch = min(10, domainsArray.count)
            let domainsToFetch = Array(domainsArray.prefix(upTo: numberOfDomainsToFetch))
            domainsArray = Array(domainsArray.dropFirst(numberOfDomainsToFetch))

            let handledIds = try await withThrowingTaskGroup(of: [String].self, returning: Set<String>.self) { group in
                for domain in domainsToFetch {
                    let url = URL(string: "\(URL.NavigationalScheme.https.separated())\(domain)")
                    if let ids = idsByDomain[domain], let url {
                        group.addTask { [weak self] in
                            guard let self else {
                                return []
                            }
                            return try await self.fetchAndStoreFavicon(for: url, bookmarkIds: ids)
                        }
                    }
                }

                var results = Set<String>()
                for try await value in group {
                    results.formUnion(value)
                }
                return results
            }

            ids.subtract(handledIds)
            try stateStore.storeBookmarkIDs(ids)

            try checkCancellation()
        }
    }

    private func fetchAndStoreFavicon(for url: URL, bookmarkIds: [String]) async throws -> [String] {
        let fetchResult: (Data?, URL?)
        do {
            fetchResult = try await fetcher.fetchFavicon(for: url)
        } catch {
            let nsError = error as NSError
            // if user is offline, we want to retry later
            let temporaryErrorCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorCancelled]
            if nsError.domain == NSURLErrorDomain, temporaryErrorCodes.contains(nsError.code) {
                return []
            }
            return bookmarkIds
        }

        do {
            let (imageData, imageURL) = fetchResult
            if let imageData {
                os_log(.debug, log: log, "Favicon found for %{public}s", url.absoluteString)
                try await faviconStore.storeFavicon(imageData, with: imageURL, for: url)
            } else {
                os_log(.debug, log: log, "Favicon not found for %{public}s", url.absoluteString)
            }

            try checkCancellation()
            return bookmarkIds
        } catch is CancellationError {
            os_log(.debug, log: log, "Favicon fetching cancelled")
            return []
        } catch {
            os_log(.debug, log: log, "Error storing favicon for %{public}s: %{public}s", url.absoluteString, error.localizedDescription)
            throw error
        }
    }


    private func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }

    private func mapBookmarkDomainsToUUIDs(for uuids: any Sequence & CVarArg) -> [String: [String]] {
        var idsByDomain = [String: [String]]()

        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@ AND %K == NO", #keyPath(BookmarkEntity.uuid), uuids, #keyPath(BookmarkEntity.isFolder))
        request.propertiesToFetch = [#keyPath(BookmarkEntity.url)]

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            let bookmarks = (try? context.fetch(request)) ?? []

            idsByDomain = bookmarks.reduce(into: [String: [String]]()) { partialResult, bookmark in
                if let uuid = bookmark.uuid, let domain = bookmark.url.flatMap(URL.init(string:))?.host {
                    if let ids = partialResult[domain] {
                        partialResult[domain] = ids + [uuid]
                    } else {
                        partialResult[domain] = [uuid]
                    }
                }
            }
        }
        return idsByDomain
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

    private let lock = NSRecursiveLock()

    private let database: CoreDataDatabase
    private let stateStore: BookmarksFaviconsFetcherStateStoring
    private let fetcher: FaviconFetching
    private let faviconStore: FaviconStoring

    private var _isExecuting: Bool = false
    private var _isFinished: Bool = false
    private var _didStart: (() -> Void)?
    private var _didFinish: ((Error?) -> Void)?
    private var _didReceiveHTTPRequestError: ((Error) -> Void)?
}
