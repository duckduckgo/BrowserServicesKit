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
import Networking

public protocol RemoteAPIRequestCreating {

    func createRequest(url: URL, method: HTTPRequestMethod) -> HTTPRequesting

    func createRequest(url: URL, method: HTTPRequestMethod, body: Data, contentType: String) -> HTTPRequesting

    func createRequest(url: URL, method: HTTPRequestMethod, parameters: [String : String], headers: [String : String]) -> HTTPRequesting

    func createRequest(url: URL, method: HTTPRequestMethod, headers: [String: String], body: Data, contentType: String) -> HTTPRequesting

    func createRequest(
        url: URL,
        method: HTTPRequestMethod,
        parameters: [String: String],
        headers: [String: String],
        body: Data?,
        contentType: String?
    ) -> HTTPRequesting

}

public extension RemoteAPIRequestCreating {
    func createRequest(url: URL, method: HTTPRequestMethod) -> HTTPRequesting {
        createRequest(url: url, method: method, parameters: [:], headers: [:], body: nil, contentType: nil)
    }

    func createRequest(url: URL, method: HTTPRequestMethod, body: Data, contentType: String) -> HTTPRequesting {
        let headers = ["Content-Type": contentType]
        return createRequest(url: url, method: method, parameters: [:], headers: headers, body: body, contentType: nil)
    }

    func createRequest(url: URL, method: HTTPRequestMethod, parameters: [String : String], headers: [String : String]) -> HTTPRequesting {
        createRequest(url: url, method: method, parameters: parameters, headers: headers, body: nil, contentType: nil)
    }

    func createRequest(url: URL, method: HTTPRequestMethod, headers: [String: String], body: Data, contentType: String) -> HTTPRequesting {
        createRequest(url: url, method: method, parameters: [:], headers: headers, body: body, contentType: contentType)
    }
}

public struct RemoteAPIRequestCreator: RemoteAPIRequestCreating {

    public init() { }

    public func createRequest(
        url: URL,
        method: HTTPRequestMethod,
        parameters: [String : String],
        headers: [String : String],
        body: Data?,
        contentType: String?
    ) -> HTTPRequesting {

        var requestHeaders = APIRequest.Headers().default
        requestHeaders.merge(headers, uniquingKeysWith: { $1 })
        if let contentType {
            requestHeaders["Content-Type"] = contentType
        }

        let configuration = APIRequest.Configuration(url: url, method: .init(method), queryParameters: parameters, headers: requestHeaders, body: body)

        return APIRequest(configuration: configuration)
    }
}

public enum HTTPRequestMethod: String {

    case GET
    case POST
    case PATCH
    case DELETE

}

public protocol HTTPRequesting {

    func execute() async throws -> HTTPResult

}

extension APIRequest.HTTPMethod {
    init(_ httpRequestMethod: HTTPRequestMethod) {
        switch httpRequestMethod {
        case .GET:
            self = .get
        case .POST:
            self = .post
        case .PATCH:
            self = .patch
        case .DELETE:
            self = .delete
        }
    }
}

extension APIRequest: HTTPRequesting {

    public func execute() async throws -> HTTPResult {
        let (data, response) = try await fetch()
        return .init(data: data, response: response)
    }
}

public struct HTTPResult {

    public let data: Data?
    public let response: HTTPURLResponse

}
