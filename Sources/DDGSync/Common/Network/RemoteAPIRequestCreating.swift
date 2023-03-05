//
//  RemoteAPIRequestCreating.swift
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

public protocol RemoteAPIRequestCreating {

    func createRequest(url: URL, method: HTTPRequestMethod) -> HTTPRequesting

}

public struct RemoteAPIRequestCreator: RemoteAPIRequestCreating {

    public init() { }

    public func createRequest(url: URL, method: HTTPRequestMethod) -> HTTPRequesting {
        return HTTPRequest(url: url, method: method)
    }

}

public enum HTTPRequestMethod: String {

    case GET
    case POST
    case PATCH

}

public protocol HTTPRequesting {

    mutating func addParameter(_ name: String, value: String)

    mutating func addHeader(_ name: String, value: String)

    mutating func setBody(body: Data, withContentType contentType: String)

    func execute() async throws -> HTTPResult

}

enum HTTPHeaderName {
    static let acceptEncoding = "Accept-Encoding"
    static let acceptLanguage = "Accept-Language"
    static let userAgent = "User-Agent"
    static let etag = "ETag"
    static let ifNoneMatch = "If-None-Match"
    static let moreInfo = "X-DuckDuckGo-MoreInfo"
    static let contentType = "Content-Type"
}

enum HTTPRequestError: Error {
    case failedToCreateRequestUrl
    case notHTTPURLResponse(URLResponse?)
    case bodyWithoutContentType
    case contentTypeWithoutBody
}

public struct HTTPResult {

    public let data: Data?
    public let response: HTTPURLResponse

}
