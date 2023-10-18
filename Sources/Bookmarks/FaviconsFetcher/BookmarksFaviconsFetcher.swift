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

import CoreData
import Foundation
import Persistence
import LinkPresentation
import UniformTypeIdentifiers

public protocol FaviconFetching {
    func fetchFavicon(for url: URL) async throws -> Data?
}

public protocol FaviconStoring {
    func storeFavicon(_ imageData: Data, for url: URL) async throws
}

public final class FaviconFetcher: NSObject, FaviconFetching, URLSessionTaskDelegate {

    public override init() {}

    public func fetchFavicon(for url: URL) async throws -> Data? {
        let metadataFetcher = LPMetadataProvider()
        let metadata: LPLinkMetadata = try await {
            if #available(iOS 15.0, macOS 12.0, *) {
                var request = URLRequest(url: url)
                request.attribution = .user
                return try await metadataFetcher.startFetchingMetadata(for: request)
            } else {
                return try await metadataFetcher.startFetchingMetadata(for: url)
            }
        }()

        guard let iconProvider = metadata.iconProvider else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            iconProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { data, error in
                guard let data = data as? Data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}

public final class BookmarksFaviconsFetcher {

    public init(database: CoreDataDatabase, metadataStore: BookmarkFaviconsMetadataStoring, fetcher: FaviconFetching, store: FaviconStoring) {
        self.database = database
        self.metadataStore = metadataStore
        self.fetcher = fetcher
        self.faviconStore = store
    }

    public func startFetching(with modifiedBookmarkIDs: Set<String>, deletedBookmarkIDs: Set<String> = []) async throws {
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
                                    print("Favicon found for \(url)")
                                    try await self.faviconStore.storeFavicon(image, for: url)
                                    return nil
                                } else {
                                    print("Favicon not found for \(url)")
                                    return id
                                }
                            } catch {
                                print("ERROR: \(error)")
                                return nil
                            }
                        }
                    }
                }

                var results = Set<String>()
                for try await value in group {
                    if let value {
                        results.insert(value)
                    }
                }
                return results
            }

            idsWithoutFavicons.formUnion(newIdsWithoutFavicons)
        }
    }

    private let database: CoreDataDatabase
    private let metadataStore: BookmarkFaviconsMetadataStoring
    private let fetcher: FaviconFetching
    private let faviconStore: FaviconStoring

    private func fetchBookmarks(with uuids: any Sequence & CVarArg, in context: NSManagedObjectContext) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K IN %@ AND %K == NO", #keyPath(BookmarkEntity.uuid), uuids, #keyPath(BookmarkEntity.isFolder))
        request.propertiesToFetch = [#keyPath(BookmarkEntity.url)]

        return (try? context.fetch(request)) ?? []
    }
}

