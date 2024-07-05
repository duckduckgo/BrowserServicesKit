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
import Network

extension URL {

    public static let empty = (NSURL(string: "") ?? NSURL()) as URL

    public var isEmpty: Bool {
        absoluteString.isEmpty
    }

    public func matches(_ other: URL) -> Bool {
        let string1 = self.absoluteString
        let string2 = other.absoluteString
        return string1.droppingHashedSuffix().dropping(suffix: "/").appending(string1.hashedSuffix ?? "")
            == string2.droppingHashedSuffix().dropping(suffix: "/").appending(string2.hashedSuffix ?? "")
    }

    /// URL without the scheme and the '/' suffix of the path.  
    /// Useful for finding duplicate URLs
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

    public struct NavigationalScheme: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public static let separator = "://"

        public static let http = NavigationalScheme(rawValue: "http")
        public static let https = NavigationalScheme(rawValue: "https")
        public static let ftp = NavigationalScheme(rawValue: "ftp")
        public static let file = NavigationalScheme(rawValue: "file")
        public static let data = NavigationalScheme(rawValue: "data")
        public static let blob = NavigationalScheme(rawValue: "blob")
        public static let about = NavigationalScheme(rawValue: "about")

        public static let mailto = NavigationalScheme(rawValue: "mailto")

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public func separated() -> String {
            if case .mailto = self {
                return self.rawValue + ":"
            }
            return self.rawValue + Self.separator
        }

        public static var navigationalSchemes: [NavigationalScheme] {
            return [.http, .https, .ftp, .file, .data, .blob, .about]
        }

        public static var schemesWithRemovableBasicAuth: [NavigationalScheme] {
            return [.http, .https, .ftp, .file]
        }

        public static var hypertextSchemes: [NavigationalScheme] {
            return [.http, .https]
        }

        public static var punycodeEncodableSchemes: [NavigationalScheme] {
            return [.http, .https, .ftp, .mailto]
        }

        public var defaultPort: Int? {
            switch self {
            case .http: return 80
            case .https: return 443
            case .ftp: return 23
            default: return nil
            }
        }
    }

    public var navigationalScheme: NavigationalScheme? {
        self.scheme.map(NavigationalScheme.init(rawValue:))
    }

    public var isValid: Bool {
        guard let navigationalScheme else { return false }

        if NavigationalScheme.hypertextSchemes.contains(navigationalScheme) {
           return host?.isValidHost == true
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

        let url: URL?
        let urlWithScheme: URL?
        if #available(macOS 14.0, iOS 17.0, *) {
            // Making sure string is strictly valid according to the RFC
            url = URL(string: s, encodingInvalidCharacters: false)
            urlWithScheme = URL(string: NavigationalScheme.http.separated() + s, encodingInvalidCharacters: false)
        } else {
            url = URL(string: s)
            urlWithScheme = URL(string: NavigationalScheme.http.separated() + s)
        }

        if let url {
            // if URL has domain:port or user:password@domain mistakengly interpreted as a scheme
            if url.navigationalScheme != .mailto,
               let urlWithScheme,
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
                if IPv4Address(String(hostname)) != nil {
                    // Require 4 octets specified explicitly for an IPv4 address (avoid 1.4 -> 1.0.0.4 expansion)
                    guard hostname.split(separator: ".").count == 4 else {
                        return nil
                    }
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

        let supportedSchemes = NavigationalScheme.punycodeEncodableSchemes
        if let navigationalScheme = supportedSchemes.first(where: { s.hasPrefix($0.separated()) }) {
            scheme = navigationalScheme.separated()
            s = s.dropping(prefix: scheme)
        } else if !s.contains(".") {
            return nil
        } else if s.hasPrefix("#") {
            return nil
        } else {
            scheme = URL.NavigationalScheme.http.separated()
        }

        guard let (authData, urlPart, query) = Self.fixupAndSplitURLString(s) else { return nil }

        let componentsWithoutQuery = urlPart.split(separator: "/").map(String.init)
        guard !componentsWithoutQuery.isEmpty else {
            return nil
        }

        let host = componentsWithoutQuery[0].punycodeEncodedHostname

        let encodedPath = componentsWithoutQuery
            .dropFirst()
            .map { $0.percentEncoded(withAllowedCharacters: .urlPathAllowed) }
            .joined(separator: "/")

        let hostPathSeparator = !encodedPath.isEmpty || urlPart.hasSuffix("/") ? "/" : ""
        let url = scheme + (authData != nil ? String(authData!) + "@" : "") + host + hostPathSeparator + encodedPath + query

        self.init(string: url)
    }

    private static func fixupAndSplitURLString(_ s: String) -> (authData: String.SubSequence?, domainAndPath: String.SubSequence, query: String)? {
        let urlAndFragment = s.split(separator: "#", maxSplits: 1)
        guard !urlAndFragment.isEmpty else { return nil }

        let authDataAndUrl = urlAndFragment[0].split(separator: "@", maxSplits: 1)
        guard !authDataAndUrl.isEmpty else { return nil }

        let urlAndQuery = authDataAndUrl.last!.split(separator: "?", maxSplits: 1)
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
        } else if urlAndFragment[0].hasSuffix("?") {
            query = "?"
        }
        if urlAndFragment.count > 1 {
            query += "#" + urlAndFragment[1].percentEncoded(withAllowedCharacters: .urlQueryStringAllowed)
        } else if s.hasSuffix("#") {
            query += "#"
        }

        return (authData: authDataAndUrl.count > 1 && !authDataAndUrl[0].isEmpty ? authDataAndUrl[0] : nil,
                domainAndPath: urlAndQuery[0],
                query: query)
    }

    public func replacing(host: String?) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.host = host
        return components.url
    }

    /// returns true if URLs are equal except the #fragment part
    public func isSameDocument(_ other: URL) -> Bool {
        self.absoluteString.droppingHashedSuffix() == other.absoluteString.droppingHashedSuffix()
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

    public func appendingParameters<QueryParams: Collection>(_ parameters: QueryParams, allowedReservedCharacters: CharacterSet? = nil) -> URL
    where QueryParams.Element == (key: String, value: String) {

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
        appending(percentEncodedQueryItems: [percentEncodedQueryItem])
    }

    public func appending(percentEncodedQueryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }

        var existingPercentEncodedQueryItems = components.percentEncodedQueryItems ?? [URLQueryItem]()
        existingPercentEncodedQueryItems.append(contentsOf: percentEncodedQueryItems)
        components.percentEncodedQueryItems = existingPercentEncodedQueryItems

        return components.url ?? self
    }

    public func getQueryItems() -> [URLQueryItem]? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let encodedQuery = components.percentEncodedQuery
        else { return nil }
        components.percentEncodedQuery = encodedQuery.encodingPlusesAsSpaces()
        return components.queryItems ?? nil
    }

    public func getQueryItem(named name: String) -> URLQueryItem? {
        getQueryItems()?.first(where: { queryItem -> Bool in
            queryItem.name == name
        })
    }

    public func getParameter(named name: String) -> String? {
        getQueryItem(named: name)?.value
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

    // MARK: Basic Auth username/password

    public var basicAuthCredential: URLCredential? {
        guard let navigationalScheme,
              NavigationalScheme.schemesWithRemovableBasicAuth.contains(navigationalScheme),
              let user = self.user?.removingPercentEncoding else { return nil }

        return URLCredential(user: user, password: self.password?.removingPercentEncoding ?? "", persistence: .forSession)
    }

    public func removingBasicAuthCredential() -> URL {
        guard let navigationalScheme,
              NavigationalScheme.schemesWithRemovableBasicAuth.contains(navigationalScheme),
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }

        components.user = nil
        components.password = nil

        return components.url ?? self
    }

    public var basicAuthProtectionSpace: URLProtectionSpace? {
        guard let host, let scheme else {
            return nil
        }
        return URLProtectionSpace(host: host,
                                  port: port ?? navigationalScheme?.defaultPort ?? 0,
                                  protocol: scheme,
                                  realm: nil,
                                  authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
    }

    public func matches(_ protectionSpace: URLProtectionSpace) -> Bool {
        return host == protectionSpace.host && (port ?? navigationalScheme?.defaultPort) == protectionSpace.port && scheme == protectionSpace.protocol
    }

}

public extension CharacterSet {

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
