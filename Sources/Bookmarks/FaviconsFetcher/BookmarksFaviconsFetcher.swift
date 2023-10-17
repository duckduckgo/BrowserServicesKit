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
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public protocol BookmarkFaviconsMetadataStoring {
    func getBookmarkIDs() throws -> Set<String>
    func storeBookmarkIDs(_ ids: Set<String>) throws

    func getDomainsWithoutFavicon() throws -> Set<String>
    func storeDomainsWithoutFavicon(_ domains: Set<String>) throws
}

public class BookmarkFaviconsMetadataStorage: BookmarkFaviconsMetadataStoring {

    let dataDirectoryURL: URL
    let missingIDsFileURL: URL
    let domainsWithoutFaviconURL: URL

    public init(applicationSupportURL: URL) {
        dataDirectoryURL = applicationSupportURL.appendingPathComponent("FaviconsFetcher")
        missingIDsFileURL = dataDirectoryURL.appendingPathComponent("missingIDs")
        domainsWithoutFaviconURL = dataDirectoryURL.appendingPathComponent("domainsWithoutFavicon")

        initStorage()
    }

    private func initStorage() {
        if !FileManager.default.fileExists(atPath: dataDirectoryURL.path) {
            try! FileManager.default.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: missingIDsFileURL.path) {
            try! FileManager.default.createFile(atPath: missingIDsFileURL.path, contents: Data())
        }
        if !FileManager.default.fileExists(atPath: domainsWithoutFaviconURL.path) {
            try! FileManager.default.createFile(atPath: domainsWithoutFaviconURL.path, contents: Data())
        }
    }

    public func getBookmarkIDs() throws -> Set<String> {
        let data = try Data(contentsOf: missingIDsFileURL)
        guard let rawValue = String(data: data, encoding: .utf8) else {
            return []
        }
        return Set(rawValue.components(separatedBy: ","))
    }

    public func storeBookmarkIDs(_ ids: Set<String>) throws {
        try ids.joined(separator: ",").data(using: .utf8)?.write(to: missingIDsFileURL)
    }

    public func getDomainsWithoutFavicon() throws -> Set<String> {
        let data = try Data(contentsOf: domainsWithoutFaviconURL)
        guard let rawValue = String(data: data, encoding: .utf8) else {
            return []
        }
        return Set(rawValue.components(separatedBy: ","))
    }

    public func storeDomainsWithoutFavicon(_ domains: Set<String>) throws {
        try domains.joined(separator: ",").data(using: .utf8)?.write(to: domainsWithoutFaviconURL)
    }
}

public protocol FaviconFetching {

    func fetchFaviconLinks(for url: URL) async throws -> [URL]

#if os(macOS)
    func fetchFavicon(for url: URL) async throws -> NSImage?
#elseif os(iOS)
    func fetchFavicon(for url: URL) async throws -> UIImage?
#endif
}

public protocol FaviconStoring {
#if os(macOS)
    func storeFavicon(_ image: NSImage, for domain: String) async throws
#elseif os(iOS)
    func storeFavicon(_ image: UIImage, for domain: String) async throws
#endif
}

public struct BookmarkFaviconLinks {
    let documentURL: URL
    let links: [FaviconLink]
}

public final class FaviconFetcher: FaviconFetching, URLSessionTaskDelegate {

    public init() {}

    private(set) lazy var faviconsURLSession = URLSession(configuration: .ephemeral, delegate: self)

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        return request
    }

    public func fetchFaviconLinks(for url: URL) async throws -> BookmarkFaviconLinks {
        let data = try await faviconsURLSession.data(from: url)
        let links = FaviconsLinksExtractor(data: data).extractLinks()
        return BookmarkFaviconLinks(documentURL: url, links: links)
    }

#if os(macOS)
    public func fetchFavicon(for domain: String) async throws -> NSImage? {
        guard let url = URL(string: "https://\(domain)") else {
            return nil
        }

        let metadataFetcher = LPMetadataProvider()
        let metadata: LPLinkMetadata = try await {
            if #available(macOS 12.0, *) {
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
            iconProvider.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { data, error in
                guard let data = data as? Data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: NSImage(data: data))
            }
        }
    }
#elseif os(iOS)
    public func fetchFavicon(for domain: String) async throws -> UIImage? {
        guard let url = URL(string: "https://\(domain)") else {
            return nil
        }

        let metadataFetcher = LPMetadataProvider()
        let metadata: LPLinkMetadata = try await {
            if #available(iOS 15.0, *) {
                var request = URLRequest(url: url)
                request.attribution = .user
                try await metadataFetcher.startFetchingMetadata(for: request)
            } else {
                try await metadataFetcher.startFetchingMetadata(for: url)
            }
        }()

        guard let iconProvider = metadata.iconProvider else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            iconProvider.loadObject(ofClass: UIImage.self) { potentialImage, _ in
                continuation.resume(returning: potentialImage as? UIImage)
            }
        }
    }
#endif
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
        try metadataStore.storeBookmarkIDs(ids)

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        var idsArray = Array(ids)

        while !idsArray.isEmpty {
            let numberOfIdsToFetch = min(10, idsArray.count)
            let idsToFetch = Array(idsArray.prefix(upTo: numberOfIdsToFetch))
            idsArray = Array(idsArray.dropFirst(numberOfIdsToFetch))

            var urls = [String]()
            context.performAndWait {
                let bookmarks = fetchBookmarks(with: idsToFetch, in: context)
                urls = bookmarks.compactMap(\.url)
            }

            for urlString in urls {
                if let domain = URL(string: urlString)?.host, let image = try await fetcher.fetchFavicon(for: domain) {
                    try await faviconStore.storeFavicon(image, for: domain)
                }
            }
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

