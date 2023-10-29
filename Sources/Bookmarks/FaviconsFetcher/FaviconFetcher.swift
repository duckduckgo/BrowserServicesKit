//
//  FaviconFetcher.swift
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
import LinkPresentation
import UniformTypeIdentifiers

public protocol FaviconFetching {
    func fetchFavicon(for url: URL) async throws -> Data?
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

        let imageData: Data? = await withCheckedContinuation { continuation in
            iconProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { data, error in
                guard let data = data as? Data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }

        guard let imageData else {
            return try await lookUpHardcodedFaviconPath(for: url)
        }

        return imageData
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        return request
    }

    private func lookUpHardcodedFaviconPath(for url: URL) async throws -> Data? {
        guard let host = url.host else {
            return nil
        }
        var faviconImageData: Data?
        for path in ["apple-touch-icon.png", "favicon.ico"] {
            guard let faviconURL = URL(string: "\(URL.NavigationalScheme.https.separated())\(host)/\(path)") else {
                continue
            }
            let (data, response) = try await faviconsURLSession.data(from: faviconURL)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                faviconImageData = data
                break
            }
        }
        return faviconImageData
    }

    private(set) lazy var faviconsURLSession = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
}
