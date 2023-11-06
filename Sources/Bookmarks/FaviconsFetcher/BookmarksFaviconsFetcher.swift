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

import Common
import CoreData
import Foundation
import Persistence

public protocol FaviconStoring {
    func hasFavicon(for domain: String) -> Bool
    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws
}

public final class BookmarksFaviconsFetcher {

    public init(
        database: CoreDataDatabase,
        metadataStore: BookmarkFaviconsMetadataStoring,
        fetcher: FaviconFetching,
        store: FaviconStoring,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.database = database
        self.metadataStore = metadataStore
        self.fetcher = fetcher
        self.faviconStore = store
        self.getLog = log
    }

    public func startFetching(with modifiedBookmarkIDs: Set<String>, deletedBookmarkIDs: Set<String> = []) {
        cancelOngoingFetchingIfNeeded()
        let operation = FaviconsFetchOperation(
            database: database,
            metadataStore: metadataStore,
            fetcher: fetcher,
            faviconStore: faviconStore,
            modifiedBookmarkIDs: modifiedBookmarkIDs,
            deletedBookmarkIDs: deletedBookmarkIDs,
            log: self.log
        )
        operationQueue.addOperation(operation)
    }

    public func cancelOngoingFetchingIfNeeded() {
        operationQueue.cancelAllOperations()
    }

    let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.duckduckgo.sync.faviconsFetcher"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let database: CoreDataDatabase
    private let metadataStore: BookmarkFaviconsMetadataStoring
    private let fetcher: FaviconFetching
    private let faviconStore: FaviconStoring

    private var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog
}

