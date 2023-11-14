//
//  BookmarksFaviconsFetcher.swift
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

import Combine
import Common
import CoreData
import Foundation
import Persistence

public protocol FaviconStoring {
    func hasFavicon(for domain: String) -> Bool
    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws
}

public enum BookmarksFaviconsFetcherError: CustomNSError {
    case failedToStoreBookmarkIDs(Error)
    case failedToRetrieveBookmarkIDs(Error)
    case other(Error)

    public static let errorDomain: String = "BookmarksFaviconsFetcherError"

    public var errorCode: Int {
        switch self {
        case .failedToStoreBookmarkIDs:
            return 1
        case .failedToRetrieveBookmarkIDs:
            return 2
        case .other:
            return 255
        }
    }

    public var underlyingError: Error {
        switch self {
        case .failedToStoreBookmarkIDs(let error), .failedToRetrieveBookmarkIDs(let error), .other(let error):
            return error
        }
    }
}

public final class BookmarksFaviconsFetcher {

    @Published public private(set) var isFetchingInProgress: Bool = false
    public let fetchingDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never>

    public init(
        database: CoreDataDatabase,
        stateStore: BookmarksFaviconsFetcherStateStoring,
        fetcher: FaviconFetching,
        faviconStore: FaviconStoring,
        errorEvents: EventMapping<BookmarksFaviconsFetcherError>?,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.database = database
        self.stateStore = stateStore
        self.fetcher = fetcher
        self.faviconStore = faviconStore
        self.errorEvents = errorEvents
        self.getLog = log

        fetchingDidFinishPublisher = fetchingDidFinishSubject.eraseToAnyPublisher()

        isFetchingInProgressCancellable = Publishers
            .Merge(fetchingDidStartSubject.map({ true }), fetchingDidFinishSubject.map({ _ in false }))
            .prepend(false)
            .removeDuplicates()
            .assign(to: \.isFetchingInProgress, onWeaklyHeld: self)
    }

    public func initializeFetcherState() {
        cancelOngoingFetchingIfNeeded()
        operationQueue.addOperation {
            do {
                let allBookmarkIDs = self.fetchAllBookmarksUUIDs()
                try self.stateStore.storeBookmarkIDs(allBookmarkIDs)
            } catch {
                os_log(.debug, log: self.log, "Error updating bookmark IDs: %{public}s", error.localizedDescription)
                if let fetcherError = error as? BookmarksFaviconsFetcherError {
                    self.errorEvents?.fire(fetcherError)
                } else {
                    self.errorEvents?.fire(.other(error))
                }
            }
        }
    }

    public func updateBookmarkIDs(modified: Set<String>, deleted: Set<String>) {
        cancelOngoingFetchingIfNeeded()
        operationQueue.addOperation {
            do {
                let ids = try self.stateStore.getBookmarkIDs().union(modified).subtracting(deleted)
                try self.stateStore.storeBookmarkIDs(ids)
            } catch {
                os_log(.debug, log: self.log, "Error updating bookmark IDs: %{public}s", error.localizedDescription)
                if let fetcherError = error as? BookmarksFaviconsFetcherError {
                    self.errorEvents?.fire(fetcherError)
                } else {
                    self.errorEvents?.fire(.other(error))
                }
            }
        }
    }

    public func startFetching() {
        cancelOngoingFetchingIfNeeded()
        let operation = FaviconsFetchOperation(
            database: database,
            stateStore: stateStore,
            fetcher: fetcher,
            faviconStore: faviconStore,
            log: self.log
        )
        operation.didStart = { [weak self] in
            self?.fetchingDidStartSubject.send()
        }
        operation.didFinish = { [weak self] error in
            if let error {
                self?.fetchingDidFinishSubject.send(.failure(error))
                if let fetcherError = error as? BookmarksFaviconsFetcherError {
                    self?.errorEvents?.fire(fetcherError)
                } else {
                    self?.errorEvents?.fire(.other(error))
                }
            } else {
                self?.fetchingDidFinishSubject.send(.success(()))
            }
        }
        operationQueue.addOperation(operation)
    }

    public func cancelOngoingFetchingIfNeeded() {
        operationQueue.cancelAllOperations()
    }

    let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.duckduckgo.sync.bookmarksFaviconsFetcher"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private func fetchAllBookmarksUUIDs() -> Set<String> {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        var ids = [String]()

        context.performAndWait {
            let bookmarks = BookmarkUtils.fetchAllBookmarks(in: context)
            ids = bookmarks.compactMap(\.uuid)
        }

        return Set(ids)
    }

    private let errorEvents: EventMapping<BookmarksFaviconsFetcherError>?
    private let database: CoreDataDatabase
    private let stateStore: BookmarksFaviconsFetcherStateStoring
    private let fetcher: FaviconFetching
    private let faviconStore: FaviconStoring

    private var isFetchingInProgressCancellable: AnyCancellable?
    private let fetchingDidStartSubject = PassthroughSubject<Void, Never>()
    private let fetchingDidFinishSubject = PassthroughSubject<Result<Void, Error>, Never>()

    private var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog
}

