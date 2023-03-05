//
//  HTTPRequest.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

struct HTTPRequest: HTTPRequesting {

    enum Timeout {

        case none, short, long
        
    }
    
    let appVersion: AppVersion = AppVersion()
    let url: URL
    let method: HTTPRequestMethod

    private var defaultHeaders: [String: String] {
        let acceptEncoding = "gzip;q=1.0, compress;q=0.5"
        let languages = Locale.preferredLanguages.prefix(6)
        let acceptLanguage = languages.enumerated().map { index, language in
            let q = 1.0 - (Double(index) * 0.1)
            return "\(language);q=\(q)"
        }.joined(separator: ", ")

        return [
            HTTPHeaderName.acceptEncoding: acceptEncoding,
            HTTPHeaderName.acceptLanguage: acceptLanguage,
            HTTPHeaderName.userAgent: userAgent
        ]
    }

    private var userAgent: String {
#if os(macOS)
        let ddg = "mac"
        let platform = "macOS"
#elseif os(iOS)
        let ddg = "ios"
        let platform = "iOS"
#endif
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return "ddg_\(ddg)/\(appVersion.versionNumber) (\(appVersion.identifier); \(platform) \(osVersion))"
    }

    private var queryItems: [URLQueryItem]?
    private var body: Data?
    private var contentType: String?
    private var customHeaders: [String: String]?

    init(url: URL, method: HTTPRequestMethod) {
        self.url = url
        self.method = method
    }

    mutating public func setBody(body: Data, withContentType contentType: String) {
        self.body = body
        self.contentType = contentType
    }

    mutating public func addParameter(_ name: String, value: String) {
        if queryItems == nil {
            queryItems = [URLQueryItem]()
        }
        queryItems?.append(URLQueryItem(name: name, value: value))
    }

    mutating public func addHeader(_ name: String, value: String) {
        if customHeaders == nil {
            customHeaders = [:]
        }
        customHeaders?[name] = value
    }

    public func execute() async throws -> HTTPResult {
        if body != nil, contentType == nil {
            throw HTTPRequestError.bodyWithoutContentType
        }

        if contentType != nil, body == nil {
            throw HTTPRequestError.contentTypeWithoutBody
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url(relativeTo: nil) else {
            throw HTTPRequestError.failedToCreateRequestUrl
        }

        var request = URLRequest(url: url)

        request.httpMethod = method.rawValue

        defaultHeaders.forEach { header in
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        customHeaders?.forEach { header in
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        if let body = body, let contentType = contentType {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: HTTPHeaderName.contentType)
        }

        // When we can use iOS 15 and macOS 12 only we can just use the async/await APIs for URL requests.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPResult, Error>) in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let httpResponse = response as? HTTPURLResponse {
                    continuation.resume(returning: HTTPResult(data: data, response: httpResponse))
                } else {
                    continuation.resume(throwing: HTTPRequestError.notHTTPURLResponse(response))
                }
            }
            
            task.resume()
        }
    }

}
