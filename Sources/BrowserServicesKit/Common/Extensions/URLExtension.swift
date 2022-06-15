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

    public struct NavigationalScheme: RawRepresentable, Hashable {
        public let rawValue: String

        public static let separator = "://"

        public static let http = NavigationalScheme(rawValue: "http")
        public static let https = NavigationalScheme(rawValue: "https")
        public static let ftp = NavigationalScheme(rawValue: "ftp")
        public static let file = NavigationalScheme(rawValue: "file")
        public static let data = NavigationalScheme(rawValue: "data")
        public static let blob = NavigationalScheme(rawValue: "blob")
        public static let about = NavigationalScheme(rawValue: "about")

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public func separated() -> String {
            self.rawValue + Self.separator
        }

        public static var navigationalSchemes: [NavigationalScheme] {
            return [.http, .https, .ftp, .file, .data, .blob, .about]
        }

        public static var hypertextSchemes: [NavigationalScheme] {
            return [.http, .https]
        }
    }

    public var isValid: Bool {
        guard let scheme = scheme.map(NavigationalScheme.init) else { return false }

        if NavigationalScheme.hypertextSchemes.contains(scheme) {
           return host?.isValidHost == true && user == nil
        }

        // This effectively allows file:// and External App Scheme URLs to be entered by user
        // Without this check single word entries get treated like domains
        return true
    }

    /// URL and URLComponents can't cope with emojis and international characters so this routine does some manual processing while trying to
    /// retain the input as much as possible.
    public init?(trimmedAddressBarString: String) {
        var s = trimmedAddressBarString

        // Creates URL even if user enters one slash "/" instead of two slashes "//" after the hypertext scheme component
        if let scheme = NavigationalScheme.hypertextSchemes.first(where: { s.hasPrefix($0.rawValue + ":/") }),
           !s.hasPrefix(scheme.separated()) {
            s = scheme.separated() + s.dropFirst(scheme.separated().count - 1)
        }

        if let url = URL(string: s) {
            // if URL has domain:port or user:password@domain mistakengly interpreted as a scheme
            if let urlWithScheme = URL(string: NavigationalScheme.http.separated() + s),
               urlWithScheme.port != nil || urlWithScheme.user != nil {
                // could be a local domain but user needs to use the protocol to specify that
                // make exception for "localhost"
                guard urlWithScheme.host?.contains(".") == true || urlWithScheme.host == .localhost else { return nil }
                self = urlWithScheme
                return

            } else if url.scheme != nil {
                self = url
                return

            } else if let hostname = s.split(separator: "/").first {
                guard hostname.contains(".") || String(hostname) == .localhost else {
                    // could be a local domain but user needs to use the protocol to specify that
                    return nil
                }
            } else {
                return nil
            }

            s = NavigationalScheme.http.separated() + s
        }

        self.init(punycodeEncodedString: s)
    }

    private init?(punycodeEncodedString: String) {
        var s = punycodeEncodedString
        let scheme: String

        if s.hasPrefix(URL.NavigationalScheme.http.separated()) {
            scheme = URL.NavigationalScheme.http.separated()
        } else if s.hasPrefix(URL.NavigationalScheme.https.separated()) {
            scheme = URL.NavigationalScheme.https.separated()
        } else if !s.contains(".") {
            return nil
        } else {
            scheme = URL.NavigationalScheme.http.separated()
            s = scheme + s
        }

        let urlAndQuery = s.split(separator: "?", maxSplits: 1)
        guard !urlAndQuery.isEmpty, !urlAndQuery[0].contains(" ") else {
            return nil
        }

        var query = ""
        if urlAndQuery.count > 1 {
            // escape invalid characters with %20 in query values
            do {
                struct Throwable: Error {}
                query = try "?" + urlAndQuery[1].split(separator: "&").map { component in
                    try component.split(separator: "=", maxSplits: 1).enumerated().map { idx, component -> String in
                        // don't allow spaces in query names
                        guard !(idx == 0 && component.contains(" ")),
                              let encoded = component.addingPercentEncoding(withAllowedCharacters: .urlQueryParameterAllowed)
                        else {
                            throw Throwable()
                        }
                        return encoded
                    }.joined(separator: "=")
                }.joined(separator: "&")
            } catch {
                return nil
            }
        }

        let componentsWithoutQuery = urlAndQuery[0].split(separator: "/").dropFirst().map(String.init)
        guard !componentsWithoutQuery.isEmpty else {
            return nil
        }

        let host = componentsWithoutQuery[0].punycodeEncodedHostname

        let encodedPath = componentsWithoutQuery
            .dropFirst()
            .map { $0.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlPathAllowed) ?? $0 }
            .joined(separator: "/")

        let hostPathSeparator = !encodedPath.isEmpty || urlAndQuery[0].hasSuffix("/") ? "/" : ""
        let url = scheme + host + hostPathSeparator + encodedPath + query

        self.init(string: url)
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

    public func addParameter(name: String, value: String, allowedReservedCharacters: CharacterSet? = nil) throws -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { throw ParameterError.parsingFailed }
        
        let allowedCharacters: CharacterSet = {
            if let allowedReservedCharacters = allowedReservedCharacters {
                return .urlQueryParameterAllowed.union(allowedReservedCharacters)
            }
            return .urlQueryParameterAllowed
        }()
        
        guard let percentEncodedName = name.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
              let percentEncodedValue = value.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
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
