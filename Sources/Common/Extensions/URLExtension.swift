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

    public func matches(_ other: URL) -> Bool {
        return self.absoluteString.dropping(suffix: "/") == other.absoluteString.dropping(suffix: "/")
    }

    // URL without the scheme and the '/' suffix of the path
    // For finding duplicate URLs
    public var naked: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.scheme = nil
        components.host = components.host?.droppingWwwPrefix()
        if components.path.last == "/" {
            components.path.removeLast()
        }
        return components.url
    }

    public var nakedString: String? {
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

    public var securityOrigin: SecurityOrigin {
        SecurityOrigin(protocol: self.scheme ?? "",
                       host: self.host ?? "",
                       port: self.port ?? 0)
    }
    
    public func isPart(ofDomain domain: String) -> Bool {
        guard let host = host else { return false }
        return host == domain || host.hasSuffix(".\(domain)")
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
        } else if s.hasPrefix("#") {
            return nil
        } else {
            scheme = URL.NavigationalScheme.http.separated()
            s = scheme + s
        }

        guard let (urlPart, query) = Self.fixupAndSplitURLString(s) else { return nil }

        let componentsWithoutQuery = urlPart.split(separator: "/").dropFirst().map(String.init)
        guard !componentsWithoutQuery.isEmpty else {
            return nil
        }

        let host = componentsWithoutQuery[0].punycodeEncodedHostname

        let encodedPath = componentsWithoutQuery
            .dropFirst()
            .map { $0.percentEncoded(withAllowedCharacters: .urlPathAllowed) }
            .joined(separator: "/")

        let hostPathSeparator = !encodedPath.isEmpty || urlPart.hasSuffix("/") ? "/" : ""
        let url = scheme + host + hostPathSeparator + encodedPath + query

        self.init(string: url)
    }

    private static func fixupAndSplitURLString(_ s: String) -> (urlPart: String.SubSequence, query: String)? {
        let urlAndHash = s.split(separator: "#", maxSplits: 1)
        guard !urlAndHash.isEmpty else { return nil }
        let urlAndQuery = urlAndHash[0].split(separator: "?", maxSplits: 1)
        guard !urlAndQuery.isEmpty, !urlAndQuery[0].contains(" ") else {
            return nil
        }

        var query = ""
        if urlAndQuery.count > 1 {
            // escape invalid characters with %20 in query values
            // keep already encoded characters and + sign in place
            do {
                struct Throwable: Error {}
                query = try "?" + urlAndQuery[1].split(separator: "&").map { component in
                    try component.split(separator: "=", maxSplits: 1).enumerated().map { idx, component -> String in
                        // don't allow spaces in parameter names
                        let isParameterName = (idx == 0)
                        guard !(isParameterName && component.contains(" ")) else { throw Throwable() }

                        return component.percentEncoded(withAllowedCharacters: .urlQueryStringAllowed)
                    }.joined(separator: "=")
                }.joined(separator: "&")
            } catch {
                return nil
            }
        } else if urlAndHash[0].hasSuffix("?") {
            query = "?"
        }
        if urlAndHash.count > 1 {
            query += "#" + urlAndHash[1].percentEncoded(withAllowedCharacters: .urlQueryStringAllowed)
        } else if s.hasSuffix("#") {
            query += "#"
        }

        return (urlAndQuery[0], query)
    }
    
    public func replacing(host: String?) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.host = host
        return components.url
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

    public func appendingParameters<C: Collection>(_ parameters: C, allowedReservedCharacters: CharacterSet? = nil) -> URL
    where C.Element == (key: String, value: String) {

        return parameters.reduce(self) { partialResult, parameter in
            partialResult.appendingParameter(
                name: parameter.key,
                value: parameter.value,
                allowedReservedCharacters: allowedReservedCharacters
            )
        }
    }

    public func appendingParameter(name: String, value: String, allowedReservedCharacters: CharacterSet? = nil) -> URL {
        let queryItem = URLQueryItem(percentEncodingName: name,
                                     value: value,
                                     withAllowedCharacters: allowedReservedCharacters)
        return self.appending(percentEncodedQueryItem: queryItem)
    }

    public func appending(percentEncodedQueryItem: URLQueryItem) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }

        var percentEncodedQueryItems = components.percentEncodedQueryItems ?? [URLQueryItem]()
        percentEncodedQueryItems.append(percentEncodedQueryItem)
        components.percentEncodedQueryItems = percentEncodedQueryItems

        return components.url ?? self
    }

    public func getParameter(named name: String) -> String? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let encodedQuery = components.percentEncodedQuery
        else { return nil }
        components.percentEncodedQuery = encodedQuery.encodingPlusesAsSpaces()
        let queryItem = components.queryItems?.first(where: { queryItem -> Bool in
            queryItem.name == name
        })
        return queryItem?.value
    }
    
    public func isThirdParty(to otherUrl: URL, tld: TLD) -> Bool {
        guard let thisHost = host else {
            return false
        }
        guard let otherHost = otherUrl.host else {
            return false
        }
        let thisRoot = tld.eTLDplus1(thisHost)
        let otherRoot = tld.eTLDplus1(otherHost)
        
        return thisRoot != otherRoot
    }

    public func removingParameters(named parametersToRemove: Set<String>) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }

        var percentEncodedQueryItems = components.percentEncodedQueryItems ?? [URLQueryItem]()
        percentEncodedQueryItems.removeAll { parametersToRemove.contains($0.name) }
        components.percentEncodedQueryItems = percentEncodedQueryItems

        return components.url ?? self
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
    static let urlQueryStringAllowed = CharacterSet(charactersIn: "%+?").union(.urlQueryParameterAllowed)

}

extension URLQueryItem {

    init(percentEncodingName name: String, value: String, withAllowedCharacters allowedReservedCharacters: CharacterSet? = nil) {
        let allowedCharacters: CharacterSet = {
            if let allowedReservedCharacters = allowedReservedCharacters {
                return .urlQueryParameterAllowed.union(allowedReservedCharacters)
            }
            return .urlQueryParameterAllowed
        }()

        let percentEncodedName = name.percentEncoded(withAllowedCharacters: allowedCharacters)
        let percentEncodedValue = value.percentEncoded(withAllowedCharacters: allowedCharacters)

        self.init(name: percentEncodedName, value: percentEncodedValue)
    }

}
