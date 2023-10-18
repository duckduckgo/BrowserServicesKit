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
            FileManager.default.createFile(atPath: missingIDsFileURL.path, contents: Data())
        }
        if !FileManager.default.fileExists(atPath: domainsWithoutFaviconURL.path) {
            FileManager.default.createFile(atPath: domainsWithoutFaviconURL.path, contents: Data())
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

public struct BookmarkFaviconLinks {
    public let documentURL: URL
    public let links: [FaviconLink]
}

public protocol FaviconFetching {

    func fetchFaviconLinks(for url: URL) async throws -> BookmarkFaviconLinks
    func searchHardcodedFaviconPaths(for url: URL) async throws -> BookmarkFaviconLinks

#if os(macOS)
    func fetchFavicon(for url: URL) async throws -> NSImage?
#elseif os(iOS)
    func fetchFavicon(for url: URL) async throws -> UIImage?
#endif
}

public protocol FaviconStoring {

    func handleFaviconLinks(_ links: BookmarkFaviconLinks) async throws

#if os(macOS)
    func storeFavicon(_ image: NSImage, for url: URL) async throws
#elseif os(iOS)
    func storeFavicon(_ image: UIImage, for url: URL) async throws
#endif
}

public final class FaviconFetcher: NSObject, FaviconFetching, URLSessionTaskDelegate {

    public override init() {}

    private(set) lazy var faviconsURLSession = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        return request
    }

    public func fetchFaviconLinks(for url: URL) async throws -> BookmarkFaviconLinks {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        guard let upgradedURL = components?.url else {
            return BookmarkFaviconLinks(documentURL: url, links: [])
        }
        let (data, response) = try await faviconsURLSession.data(from: upgradedURL)
        let baseURL = URL(string: "https://\(response.url!.host!)")!
        let links = FaviconsLinksExtractor(data: data, baseURL: baseURL).extractLinks()
        return BookmarkFaviconLinks(documentURL: url, links: links)
    }

    public func searchHardcodedFaviconPaths(for url: URL) async throws -> BookmarkFaviconLinks {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var newComponents = URLComponents()
        newComponents.scheme = "https"
        newComponents.host = components?.host
        newComponents.port = components?.port
        guard let upgradedURL = newComponents.url else {
            return BookmarkFaviconLinks(documentURL: url, links: [])
        }

        for path in ["apple-touch-icon.png", "favicon.ico"] {
            let faviconURL = upgradedURL.appendingPathComponent(path)
            var request = URLRequest(url: faviconURL)
            request.httpMethod = "HEAD"
            if let response = try await faviconsURLSession.data(for: request).1 as? HTTPURLResponse, response.statusCode == 200 {
                print("Found favicon at hardcoded path \(faviconURL)")
                return BookmarkFaviconLinks(documentURL: url, links: [.init(href: faviconURL.absoluteString, rel: "icon")])
            }
        }
        return BookmarkFaviconLinks(documentURL: url, links: [])
    }

#if os(macOS)
    public func fetchFavicon(for url: URL) async throws -> NSImage? {
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
    public func fetchFavicon(for url: URL) async throws -> UIImage? {
        let metadataFetcher = LPMetadataProvider()
        let metadata: LPLinkMetadata = try await {
            if #available(iOS 15.0, *) {
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

//                                var links = try await self.fetcher.fetchFaviconLinks(for: url)
//                                if links.links.isEmpty {
//                                    links = try await self.fetcher.searchHardcodedFaviconPaths(for: url)
//                                }
//                                if links.links.isEmpty {
//                                    print("No links for \(url)")
//                                    return id
//                                } else {
//                                    try await self.faviconStore.handleFaviconLinks(links)
//                                    return nil
//                                }
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

