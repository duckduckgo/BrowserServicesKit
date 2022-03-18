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
        (path.isEmpty || path == "/") &&
        query == nil &&
        fragment == nil &&
        user == nil &&
        password == nil
    }
    
    // MARK: - HTTP/HTTPS
    
    public enum URLProtocol: String {
        case http
        case https

        public var scheme: String {
            return "\(rawValue)://"
        }
    }

    public func toHttps() -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        guard components.scheme == URLProtocol.http.rawValue else { return self }
        components.scheme = URLProtocol.https.rawValue
        return components.url
    }
    
    public var isHttp: Bool {
        scheme == "http"
    }
    
    public var isHttps: Bool {
        scheme == "https"
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
        
        guard let percentEncodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryParameterAllowed),
              let percentEncodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryParameterAllowed)
        else {
            throw ParameterError.encodingFailed
        }
        
        var percentEncodedQueryItems = components.percentEncodedQueryItems ?? [URLQueryItem]()
        percentEncodedQueryItems.append(URLQueryItem(name: percentEncodedName, value: percentEncodedValue))
        components.percentEncodedQueryItems = percentEncodedQueryItems

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

fileprivate extension CharacterSet {

    /**
     * As per [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986#section-2.2).
     *
     * This set contains all reserved characters that are otherwise
     * included in `CharacterSet.urlQueryAllowed` but still need to be percent-escaped.
     */
    static let urlQueryReserved = CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;=")
    
    static let urlQueryParameterAllowed = CharacterSet.urlQueryAllowed.subtracting(Self.urlQueryReserved)

}
