//
//  URLExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

extension URL {

    // URL without the scheme and the '/' suffix of the path
    // For finding duplicate URLs
    var naked: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.scheme = nil
        components.host = components.host?.droppingWwwPrefix()
        if components.path.last == "/" {
            components.path.removeLast()
        }
        return components.url
    }

    var nakedString: String? {
        naked?.absoluteString.dropping(prefix: "//")
    }

    public var root: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    public var isRoot: Bool {
        return (path.isEmpty || path == "/") &&
            query == nil &&
            fragment == nil &&
            user == nil &&
            password == nil
    }
    
    // MARK: - Parameters

    public enum ParameterError: Error {
        case parsingFailed
        case encodingFailed
        case creatingFailed
    }

    public func addParameters(_ parameters: [String: String]) throws -> URL {
        var url = self

        for parameter in parameters {
            url = try url.addParameter(name: parameter.key, value: parameter.value)
        }

        return url
    }

    public func addParameter(name: String, value: String) throws -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { throw ParameterError.parsingFailed }
        var queryItems = components.queryItems ?? [URLQueryItem]()
        let newQueryItem = URLQueryItem(name: name, value: value)
        queryItems.append(newQueryItem)
        components.queryItems = queryItems
        guard let encodedQuery = components.percentEncodedQuery else { throw ParameterError.encodingFailed }
        components.percentEncodedQuery = encodedQuery.encodingPluses()
        guard let newUrl = components.url else { throw ParameterError.creatingFailed }
        return newUrl
    }

    public func getParameter(name: String) throws -> String? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { throw ParameterError.parsingFailed }
        guard let encodedQuery = components.percentEncodedQuery else { throw ParameterError.encodingFailed }
        components.percentEncodedQuery = encodedQuery.encodingPlusesAsSpaces()
        let queryItem = components.queryItems?.first(where: { (queryItem) -> Bool in
            queryItem.name == name
        })
        return queryItem?.value
    }

}
