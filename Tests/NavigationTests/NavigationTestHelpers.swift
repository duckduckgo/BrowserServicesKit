//
//  NavigationTestHelpers.swift
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

import Combine
import Common
import Foundation
import Navigation
import WebKit

// swiftlint:disable file_length
// swiftlint:disable line_length
// swiftlint:disable cyclomatic_complexity
// swiftlint:disable force_try
// swiftlint:disable force_cast
// swiftlint:disable implicit_getter
// swiftlint:disable large_tuple

typealias EncodingContext = (urls: Any, webView: WKWebView, dataSource: Any, navigationActions: UnsafeMutablePointer<[UInt64: NavAction]>, history: [UInt64: HistoryItemIdentity])
extension NavigationEvent {

    static func navigationAction(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, redirects: [NavAction]? = nil, _ isUserInitiated: NavigationAction.UserInitiated? = nil, src: FrameInfo, targ: FrameInfo? = nil, _ shouldDownload: NavigationAction.ShouldDownload? = nil) -> NavigationEvent {
        .navigationAction(.init(request, navigationType, from: currentHistoryItemIdentity, redirects: redirects, isUserInitiated, src: src, targ: targ, shouldDownload))
    }
    
    static func response(_ nav: Nav) -> NavigationEvent {
        .navigationResponse(.navigation(nav))
    }
    static func response(_ response: NavigationResponse, _ nav: Nav?) -> NavigationEvent {
        .navigationResponse(.response(response, navigation: nav))
    }

    static func willCancel(_ navigationAction: NavAction) -> NavigationEvent {
        .willCancel(navigationAction, .none)
    }

    func encoded(_ context: EncodingContext) -> String {
        let v = { () -> String in
            switch self {
            case .navigationAction(let arg, let arg2):
                if let prefs = arg2.encoded() {
                    return ".navigationAction(\(arg.navigationAction.encoded(context)), \(prefs))"
                } else {
                    return ".navigationAction" + arg.navigationAction.encoded(context).dropping(prefix: ".init")
                }
            case .willCancel(let arg, let arg2):
                return ".willCancel(\(arg.navigationAction.encoded(context))\(arg2 == .none ? "" : "," + arg2.encoded(context)))"
            case .didCancel(let arg, let arg2):
                return ".didCancel(\(arg.navigationAction.encoded(context))\(arg2 == .none ? "" : "," + arg2.encoded(context)))"
            case .navActionWillBecomeDownload(let arg):
                return ".navActionWillBecomeDownload(\(arg.navigationAction.encoded(context)))"
            case .navActionBecameDownload(let arg, let arg2):
                return ".navActionBecameDownload(\(arg.navigationAction.encoded(context)), \(urlConst(for: URL(string: arg2)!, in: context.urls)!))"
            case .willStart(let arg):
                return ".willStart(\(arg.navigationAction.encoded(context)))"
            case .didStart(let arg):
                return ".didStart(\(arg.encoded(context)))"
            case .didReceiveAuthenticationChallenge(let arg, let arg2):
                return ".didReceiveAuthenticationChallenge(\(arg.encoded()), \(arg2?.encoded(context) ?? "nil"))"
            case .navigationResponse(.response(let resp, navigation: let nav)):
                return ".response(.\(resp.encoded(context)), \(nav == nil ? "nil" : nav!.encoded(context)))"
            case .navigationResponse(.navigation(let nav)):
                return ".response(\(nav.encoded(context)))"
            case .navResponseWillBecomeDownload(let arg):
                return ".navResponseWillBecomeDownload(\(arg))"
            case .navResponseBecameDownload(let arg, let arg2):
                return ".navResponseBecameDownload(\(arg), \(urlConst(for: arg2, in: context.urls)!))"
            case .didCommit(let arg):
                return ".didCommit(\(arg.encoded(context)))"
            case .didReceiveRedirect(let arg):
                return ".didReceiveRedirect(\(arg.encoded(context)))"
            case .didFinish(let arg):
                return ".didFinish(\(arg.encoded(context)))"
            case .didFail(let arg, let arg2):
                return ".didFail(\(arg.encoded(context)), \(arg2))"
            case .didTerminate(let arg):
                return arg != nil ? ".didTerminate(\(arg!.encoded(context)))" : ".terminated"
            }
        }().replacing(regex: "\\s\\s+", with: "")

        return v.replacingOccurrences(of: "  ", with: " ").replacing(regex: "\\s*,\\s*", with: ", ").replacing(regex: "\\s*\\+\\s*", with: " + ").replacing(regex: "\\s+\\)", with: ")").replacing(regex: "Accept-Language\\\": \\\"\\S\\S-\\S\\S, ", with: "Accept-Language\": \"en-XX,").replacingOccurrences(of: ", , ", with: ", ").replacingOccurrences(of: "..", with: ".")
    }

    static var terminated = NavigationEvent.didTerminate(nil)
}

extension URLProtectionSpace {
    convenience init(_ host: String, _ port: Int = 0, _ protocol: String?, realm: String?, method: String?) {
        self.init(host: host, port: port, protocol: `protocol`, realm: realm, authenticationMethod: method)
    }
    func encoded() -> String {
        """
        .init(
            \"\(host)\"
            \(port > 0 ? ", \(port)" : "")
            \(`protocol` != nil ? ", \"\(`protocol`!)\"" : "")
            \(realm != nil ? ", realm: \"\(realm!)\"" : "")
            \(authenticationMethod.isEmpty ? "" : ", method: \"\(authenticationMethod)\"")
        )
        """
    }
}

struct Nav: Equatable {
    var navigationAction: NavAction
    var redirects: [NavAction]
    var state: NavigationState
    var isCommitted: Bool = false
    var didReceiveAuthenticationChallenge: Bool = false

    enum IsCommitted {
        case committed
    }
    enum DidReceiveAuthenticationChallenge {
        case gotAuth
    }
    init(action navigationAction: NavAction, redirects: [NavAction] = [], _ state: NavigationState, _ isCommitted: IsCommitted? = nil, _ didReceiveAuthenticationChallenge: DidReceiveAuthenticationChallenge? = nil) {
        self.navigationAction = navigationAction
        self.state = state
        self.isCommitted = isCommitted != nil
        self.didReceiveAuthenticationChallenge = didReceiveAuthenticationChallenge != nil
        self.redirects = redirects
    }

    func encoded(_ context: EncodingContext) -> String {
        "Nav(action: \(navigationAction.navigationAction.encoded(context)), \(redirects.isEmpty ? "" : "redirects: [\(redirects.map { $0.navigationAction.encoded(context) }.joined(separator: ", "))], ")\(state.encoded(context)) \(isCommitted ? ", .committed" : (didReceiveAuthenticationChallenge ? ", nil" : "")) \(didReceiveAuthenticationChallenge ? ", .gotAuth" : ""))"
    }
}

extension NavigationState {
    static func resp(_ response: URLResponse, _ isNotForMainFrame: NavigationResponse.IsNotForMainFrame? = nil, _ cantShowMIMEType: NavigationResponse.CannotShowMimeType? = nil) -> NavigationState {
        .responseReceived(.resp(response, isNotForMainFrame, cantShowMIMEType))
    }
    static func resp(_ url: URL, status: Int? = 200, mime: String? = "text/html", _ length: Int = -1, _ encoding: String? = nil, headers: [String: String]? = nil) -> NavigationState {
        if let status {
            return .responseReceived(.resp(url, status: status, mime: mime, length, encoding, headers: headers ?? .default))
        } else {
            assert(headers == nil)
            return .responseReceived(.resp(url, mime: mime, length, encoding))
        }
    }

    func encoded(_ context: EncodingContext) -> String {
        switch self {
        case .expected:
            return ".expected"
        case .started:
            return ".started"
        case .redirected:
            return ".redirected"
        case .responseReceived(let resp):
            return "." + resp.encoded(context)
        case .finished:
            return ".finished"
        case .failed(let error):
            return ".failed(WKError(\(error.encoded())))"
        }
    }
}

extension [String: String] {
    static var `default`: [String: String] {
        [
            "Server": "Swifter Unspecified",
            "Connection": "keep-alive"
        ]
    }
}
extension NavigationResponse {
    enum IsNotForMainFrame {
        case nonMain
    }
    enum CannotShowMimeType {
        case cantShow
    }
    static func resp(_ response: URLResponse, _ isNotForMainFrame: IsNotForMainFrame? = nil, _ cantShowMIMEType: CannotShowMimeType? = nil) -> NavigationResponse {
        self.init(response: response, isForMainFrame: isNotForMainFrame == nil, canShowMIMEType: cantShowMIMEType == nil)
    }
    static func resp(_ url: URL, mime: String? = "text/html", _ length: Int = -1, _ encoding: String? = nil) -> NavigationResponse {
        self.init(response: URLResponse(url: url, mimeType: mime, expectedContentLength: length, textEncodingName: encoding),
                  isForMainFrame: true, canShowMIMEType: true)
    }

    static func resp(_ url: URL, status: Int = 200, mime: String? = "text/html", _ length: Int = -1, _ encoding: String? = nil, headers: [String: String] = .default, _ isNotForMainFrame: IsNotForMainFrame? = nil, _ cantShowMIMEType: CannotShowMimeType? = nil) -> NavigationResponse {
        var headers = headers
        if length >= 0 {
            headers["Content-Length"] = String(length)
        }
        if let encoding {
            headers["Content-Encoding"] = encoding
        }
        let response = MockHTTPURLResponse(url: url, statusCode: status, mime: mime, httpVersion: nil, headerFields: headers)!
        return self.init(response: response, isForMainFrame: isNotForMainFrame == nil, canShowMIMEType: cantShowMIMEType == nil)
    }
    func encoded(_ context: EncodingContext) -> String {
        if !canShowMIMEType || !isForMainFrame {
            return ".\(response.encoded(context).dropping(suffix: ")"))\(isForMainFrame ? "" : ", .nonMain")\(canShowMIMEType ? "" : ", .cantShow"))"
        } else {
            return response.encoded(context)
        }
    }
}

class MockHTTPURLResponse: HTTPURLResponse {
    private let mime: String?
    override var mimeType: String? {
        mime ?? super.mimeType
    }
    override var suggestedFilename: String? {
        URLResponse(url: url!, mimeType: mimeType, expectedContentLength: Int(expectedContentLength), textEncodingName: textEncodingName).suggestedFilename ?? super.suggestedFilename
    }
    init?(url: URL, statusCode: Int, mime: String?, httpVersion: String? = nil, headerFields: [String: String]?) {
        self.mime = mime
        super.init(url: url, statusCode: statusCode, httpVersion: httpVersion, headerFields: headerFields)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension WKError {
    init(_ code: Int) {
        self.init(Code(rawValue: code)!)
    }
    func encoded() -> String {
        "\(self.code.rawValue)"
    }
}

private func urlConst(for url: URL, in urls: Any) -> String? {
    let m = Mirror(reflecting: urls)
    for child in m.children where (child.value as? URL)?.matches(url) == true {
        return "urls." + child.label!
    }
    if url.isEmpty {
        return ".empty"
    }
    return nil
}

private func dataConst(forLength length: Int64, in dataSource: Any) -> String {
    let m = Mirror(reflecting: dataSource)
    for child in m.children where (child.value as? Data)?.count == Int(length) {
        return "data." + child.label! + ".count"
    }
    fatalError("Data const with length \(length) not found in \(dataSource)")
}

var defaultHeaders = [
    "User-Agent": WKWebView().value(forKey: "userAgent") as! String,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
]

func req(_ string: String, _ headers: [String: String]? = defaultHeaders, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) -> URLRequest {
    req(URL(string: string)!, headers, cachePolicy: cachePolicy)
}
func req(_ url: URL, _ headers: [String: String]? = defaultHeaders, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) -> URLRequest {
    var req = URLRequest(url: url, cachePolicy: cachePolicy)
    req.allHTTPHeaderFields = headers
    return req
}

func resp(_ url: URL, mime: String? = "text/html", _ length: Int = -1, _ encoding: String? = nil) -> URLResponse {
    return URLResponse(url: url, mimeType: mime, expectedContentLength: length, textEncodingName: encoding)
}

extension URLResponse {
    func encoded(_ context: EncodingContext) -> String {
        var headers = ""
        let defaultHeaders = [String: String].default
        var headerFields = (self as? HTTPURLResponse)?.allHeaderFields as? [String: String] ?? [:]
        headerFields["Content-Length"] = nil
        if !(self is HTTPURLResponse) || headerFields == defaultHeaders {
            headers = ""
        } else if (self as? HTTPURLResponse)?.allHeaderFields != nil {
            if Set(headerFields.keys).intersection(defaultHeaders.keys).count == defaultHeaders.count {
                headers = ", headers: .default + " + headerFields.filter { $0.value != defaultHeaders[$0.key] }.encoded(context: context)
            } else {
                headers = ", headers: " + headerFields.encoded(context: context)
            }
        } else {
            headers = ", headers: nil"
        }

        return """
        resp(
            \(urlConst(for: self.url!, in: context.urls)!),
            \((self as? HTTPURLResponse)?.statusCode != 200 ? "status: " + ((self as? HTTPURLResponse).map { String($0.statusCode) } ?? "nil") + "," : "")
            \(mimeType != "text/html" ? "mime: \"\(mimeType ?? "nil")\"," : "")
            \(expectedContentLength != -1 ? "\(dataConst(forLength: expectedContentLength, in: context.dataSource))" + (textEncodingName != nil ? "," : "") : "")
            \(textEncodingName != nil ? "\"\(textEncodingName!)\"" : "")
            \(headers)
        """.replacingOccurrences(of: ", ,", with: ", ").trimmingWhitespace().dropping(suffix: ",") + ")"
    }
}

func compare<T>(_ name: String, _ lhs: T, _ rhs: T, using comparator: (T, T) -> Bool) -> String? {
    if comparator(lhs, rhs) { return nil }
    return "`\(name)`: \(lhs) not equal to \(rhs)"
}

func compare<T: TestComparable>(_ name: String, _ lhs: T, _ rhs: T) -> String? {
    if let diff = T.difference(between: lhs, and: rhs) {
        return "`\(name)`: \(diff)"
    }
    return nil
}
func compare_tc<T: TestComparable>(_ name: String, _ lhs: T, _ rhs: T) -> String? {
    compare(name, lhs, rhs)
}

func compare<T: Equatable>(_ name: String, _ lhs: T, _ rhs: T) -> String? {
    compare(name, lhs, rhs, using: ==)
}

protocol TestComparable {
    static func difference(between lhs: Self, and rhs: Self) -> String?
}

extension NavigationAction: TestComparable {

    static func difference(between lhs: NavigationAction, and rhs: NavigationAction) -> String? {
        compare("navigationType", lhs.navigationType, rhs.navigationType)
        ?? compare_tc("sourceFrame", lhs.sourceFrame, rhs.sourceFrame)
        ?? compare_tc("targetFrame", lhs.targetFrame, rhs.targetFrame)
        ?? compare("shouldDownload", lhs.shouldDownload, rhs.shouldDownload)
        ?? compare_tc("request", lhs.request, rhs.request)
        ?? compare("fromHistoryItemIdentity", lhs.fromHistoryItemIdentity, rhs.fromHistoryItemIdentity)
        ?? compare("redirectHistory", lhs.redirectHistory, rhs.redirectHistory)
    }

}
extension [NavigationAction]?: TestComparable {

    static func difference(between lhs: [NavigationAction]?, and rhs: [NavigationAction]?) -> String? {
        guard let lhs, let rhs else {
            if let lhs {
                return "\(lhs) not equal to <nil>"
            }
            if let rhs {
                return "<nil> not equal to \(rhs)"
            }
            return nil
        }
        for (i, element) in lhs.enumerated() {
            guard rhs.indices.contains(i) else {
                return "[\(i)]: \(element) not equal to <nil>"
            }
            if let diff = NavigationAction.difference(between: element, and: rhs[i]) {
                return "[\(i)]: \(diff)"
            }
        }
        if rhs.count > lhs.count {
            return "[\(lhs.count)]: <nil> not equal to \(rhs[lhs.count])"
        }
        return nil
    }

}

extension URLRequest: TestComparable {

    private func prettifiedHeaders() -> [String: String] {
        var headers = (allHTTPHeaderFields ?? [:])
        if let lang = headers["Accept-Language"] {
            headers["Accept-Language"] = lang.replacing(regex: "^\\S\\S-\\S\\S", with: "en-XX")
        }
        return headers
    }

    static func difference(between lhs: URLRequest, and rhs: URLRequest) -> String? {
        compare("url", lhs.url ?? .empty, rhs.url ?? .empty) { $0.matches($1) }
        ?? compare("httpMethod", lhs.httpMethod, rhs.httpMethod)
        ?? compare("allHTTPHeaderFields", lhs.prettifiedHeaders(), rhs.prettifiedHeaders())
        ?? compare("cachePolicy", lhs.cachePolicy, rhs.cachePolicy)
        ?? compare("timeoutInterval", lhs.timeoutInterval, rhs.timeoutInterval)
    }

}

extension FrameInfo: TestComparable {
    static func difference(between lhs: FrameInfo, and rhs: FrameInfo) -> String? {
        compare("identity", lhs.identity, rhs.identity)
        ?? compare("url", lhs.url, rhs.url) { $0.matches($1) }
        ?? compare("securityOrigin", lhs.securityOrigin, rhs.securityOrigin)
    }
}

extension NavigationActionCancellationRelatedAction {
    static var cancelled = NavigationActionCancellationRelatedAction.taskCancelled
    static func redir(_ url: URL) -> NavigationActionCancellationRelatedAction {
        .redirect(req(url))
    }
    static func redir(_ url: String) -> NavigationActionCancellationRelatedAction {
        .redirect(req(url))
    }
    func encoded(_ context: EncodingContext) -> String {
        switch self {
        case .none:
            return ""
        case .taskCancelled:
            return ".cancelled"
        case .redirect(let req):
            return ".redir(\(urlConst(for: req.url!, in: context.urls)!))"
        case .other(let userInfo):
            return "<##other: \(userInfo.debugDescription)>"
        }
    }
}

extension NavigationPreferences {
    enum JSDisabled {
        case jsDisabled
    }
    init(_ ua: String? = nil, _ contentMode: WKWebpagePreferences.ContentMode = .recommended, _ disableJs: JSDisabled? = nil) {
        self.init(userAgent: ua, contentMode: contentMode, javaScriptEnabled: disableJs == nil)
    }
    func encoded() -> String? {
        if userAgent == nil, contentMode == .recommended, javaScriptEnabled == true {
            return nil
        }
        return ".init(\(userAgent ?? "")\(contentMode == .recommended ? "" : ((userAgent == nil ? "" : ",") + (contentMode == .mobile ? ":mobile" : "desktop")))\(javaScriptEnabled == false ? ((userAgent != nil || contentMode != .recommended ? "," : "") + ".jsDisabled") : ""))"
    }
}

extension [String: String] {
    func encoded(context: EncodingContext) -> String {
        if self.isEmpty { return "[:]" }
        var result = "["
        for (idx, item) in self.enumerated() {
            if idx > 0 {
                result.append(",\n")
            }
            var value = "\"\(item.value)\""
            if let url = URL(string: item.value), let const = urlConst(for: url, in: context.urls) {
                value = const + (item.value.hasSuffix("/") ? ".separatedString" : ".string")
            }
            result.append("\"\(item.key)\": \(value)")
        }
        result.append("]")
        return result
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        lhs.merging(rhs, uniquingKeysWith: { $1 })
    }
}

extension NavigationAction {
    enum UserInitiated {
        case userInitiated
    }
    enum ShouldDownload {
        case shouldDownload
    }

    func encoded(_ context: EncodingContext) -> String {

        if context.navigationActions.pointee[self.identifier] != nil {
            return "navAct(\(self.identifier))"
        } else {
            context.navigationActions.pointee[self.identifier] = .init(self)
        }

#if _IS_USER_INITIATED_ENABLED
        let isUserInitiated = self.isUserInitiated ? ".userInitiated," : ""
#else
        let isUserInitiated = ""
#endif
        var headers = ""
        if request.allHTTPHeaderFields == defaultHeaders {
            headers = ""
        } else if let headerFields = request.allHTTPHeaderFields {
            if Set(headerFields.keys).intersection(defaultHeaders.keys).count == defaultHeaders.count {
                headers = ", defaultHeaders + " + headerFields.filter { $0.value != defaultHeaders[$0.key] }.encoded(context: context)
            } else {
                headers = ", " + headerFields.encoded(context: context)
            }
        } else {
            headers = ", nil"
        }
        switch request.cachePolicy {
        case .useProtocolCachePolicy: break
        case .reloadIgnoringLocalCacheData:
            headers += ", cachePolicy: .reloadIgnoringLocalCacheData"
        case .reloadIgnoringLocalAndRemoteCacheData:
            headers += ", cachePolicy: .reloadIgnoringLocalAndRemoteCacheData"
        case .returnCacheDataElseLoad:
            headers += ", cachePolicy: .returnCacheDataElseLoad"
        case .returnCacheDataDontLoad:
            headers += ", cachePolicy: .returnCacheDataDontLoad"
        case .reloadRevalidatingCacheData:
            headers += ", cachePolicy: .reloadRevalidatingCacheData"
        @unknown default:
            fatalError()
        }
        return """
        .init(
            req(\(urlConst(for: url, in: context.urls)!)\(headers)),
            \(navigationType.encoded(context)),
            \(fromHistoryItemIdentity != nil ? "from: " + fromHistoryItemIdentity!.encoded(context) + "," : "")
            \(redirectHistory != nil ? "redirects: [\(redirectHistory!.map { $0.encoded(context) }.joined(separator: ", "))]," : "")
            \(isUserInitiated)
            src: \(sourceFrame.encoded(context)),
            \(targetFrame == sourceFrame  ? "" : "targ: " + targetFrame.encoded(context) + ",")
            \(shouldDownload ? ".shouldDownload," : "")
        """.trimmingWhitespace().dropping(suffix: ",") +
        ")"
    }
}

extension FrameInfo {
    func encoded(_ context: EncodingContext) -> String {
        let secOrigin = (securityOrigin == url.securityOrigin ? "" : "secOrigin: " + securityOrigin.encoded(context))
        if self.isMainFrame {
            return "main(" + (url.isEmpty ? "" : urlConst(for: url, in: context.urls)! + (secOrigin.isEmpty ? "" : ", "))  + secOrigin + ")"
        } else {
            return "frame(\(identity.handle), \(urlConst(for: url, in: context.urls)!)\((secOrigin.isEmpty ? "" : ", ") + secOrigin))"
        }
    }
}

extension SecurityOrigin: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String
    public init(stringLiteral: String) {
        self = URL(string: stringLiteral)!.securityOrigin
    }

    func encoded(_ context: EncodingContext) -> String {
        let url = URL(string: self.protocol + "://" + self.host + (port > 0 ? ":\(port)" : ""))!
        if let const = urlConst(for: url, in: context.urls) {
            return const + ".securityOrigin"
        } else {
            return "\"\(url.absoluteString)\""
        }
    }
}

extension NavigationType {
    enum MiddleClick {
        case middleClick
    }
    static var link = NavigationType.linkActivated(isMiddleClick: false)
    static func link(_ middleClick: MiddleClick) -> NavigationType { .linkActivated(isMiddleClick: true) }
    static var form = NavigationType.formSubmitted
    static var formRe = NavigationType.formResubmitted
    static func backForw(_ dist: Int) -> NavigationType { .backForward(distance: dist) }
    static var restore = NavigationType.sessionRestoration

    func encoded(_ context: EncodingContext) -> String {
        switch self {
        case .linkActivated(isMiddleClick: let isMiddleClick):
            return isMiddleClick ? ".link(.middleClick)" : ".link"
        case .formSubmitted:
            return ".form"
        case .formResubmitted:
            return ".formRe"
        case .backForward(distance: let distance):
            return ".backForw(\(distance))"
        case .reload:
            return ".reload"
        case .redirect(.server):
            return ".redirect(.server)"
        case .redirect(.client(delay: let delay)) where delay != 0:
            return ".redirect(.client(delay: \(delay)))"
        case .redirect(.client):
            return ".redirect(.client)"
        case .redirect(.developer):
            return ".redirect(.developer)"
        case .sessionRestoration:
            return ".restore"
        case .other:
            return ".other"
        case .custom(let name):
            return "<##custom: \(name.rawValue)>"
        }
    }
}

extension RedirectType {
    static var client = RedirectType.client(delay: 0)
    static func client(_ delay: Int) -> RedirectType { RedirectType.client(delay: TimeInterval(delay) / 1000) }
    func encoded() -> String {
        switch self {
        case .client(delay: let delay) where delay == 0:
            return ".client"
        case .client(delay: let delay):
            return ".client(\(Int(delay * 1000)))"
        case .server:
            return ".server"
        case .developer:
            return ".developer"
        }
    }
}
extension HistoryItemIdentity {
    func encoded(_ context: EncodingContext) -> String {
        let navigationActionIdx = context.history.first(where: { $0.value == self })!.key
        return "history[\(navigationActionIdx)]"
    }
}
extension WKWebView {
    func getDistance(from historyItemIdentity: HistoryItemIdentity) -> Int? {
        if backForwardList.currentItem.map(HistoryItemIdentity.init) == historyItemIdentity {
            return 0
        }
        if let forwardIndex = backForwardList.forwardList.firstIndex(where: { $0.identity == historyItemIdentity }) {
            return forwardIndex + 1
        }
        let backList = backForwardList.backList
        if let backIndex = backList.lastIndex(where: { $0.identity == historyItemIdentity }) {
            return -(backList.count - backIndex)  // going forward from item in _reveresed_ back list to current
        }
        return nil
    }
}

extension NavigationEvent {
    func encoded() -> String {
        let m = Mirror(reflecting: self)
        let label = m.children.first!.label!

        let value = m.children.first!.value
        let mval = Mirror(reflecting: value)

        var result = ".\(label)("
        if mval.children.first?.label == "0" {
            for (idx, child) in mval.children.enumerated() {
                if idx > 0 {
                    result.append(", ")
                }
                result.append((child.value as? CustomDebugStringConvertible)?.debugDescription ?? "\(child.value)")
            }
        } else {
            result.append((value as? CustomDebugStringConvertible)?.debugDescription ?? "\(value)")
        }
        result.append(")")

        return result
    }
}
extension Array where Element == NavigationEvent {

    func encoded(with urls: Any, webView: WKWebView, dataSource: Any, history: [UInt64: HistoryItemIdentity]) -> String {
        var navigationActions = [UInt64: NavAction]()
        var result = "[\n"
        for (idx, item) in self.enumerated() {
            if idx > 0 {
                result.append(",\n")
            }
            withUnsafeMutablePointer(to: &navigationActions) { navigationActionsPtr in
                result.append("  " + item.encoded((urls: urls, webView: webView, dataSource: dataSource, navigationActions: navigationActionsPtr, history: history)))
            }
        }
        result.append("\n]")

        return result
    }

}

class NavigationDelegateProxy: NSObject, WKNavigationDelegate {
    var delegate: DistributedNavigationDelegate

    enum FinishEventsDispatchTime {
        case instant
        case beforeWillStartNavigationAction
        case afterWillStartNavigationAction
        case afterDidStartNavigationAction
    }
    var finishEventsDispatchTime: FinishEventsDispatchTime = .instant

    init(delegate: DistributedNavigationDelegate) {
        self.delegate = delegate
    }

    // forward delegate calls to DistributedNavigationDelegate
    override func responds(to selector: Selector!) -> Bool {
        delegate.responds(to: selector)
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        delegate
    }

    private var finishWorkItem: DispatchWorkItem? {
        willSet {
            guard let finishWorkItem, !finishWorkItem.isCancelled else { return }
            finishWorkItem.perform()
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        delegate.webView(webView, decidePolicyFor: navigationAction, preferences: preferences) { [self] policy, preferences in
            decisionHandler(policy, preferences)
            switch self.finishEventsDispatchTime {
            case .instant, .afterDidStartNavigationAction: break
            case .beforeWillStartNavigationAction:
                self.finishWorkItem = nil // trigger if set after decidePolicyFor callback
            case .afterWillStartNavigationAction:
                navigationAction.onDeinit {
                    self.finishWorkItem = nil
                }
            }
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        delegate.webView(webView, didStartProvisionalNavigation: navigation)
        if case .afterDidStartNavigationAction = self.finishEventsDispatchTime {
            self.finishWorkItem = nil
        }
    }

    @MainActor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard finishEventsDispatchTime != .instant else {
            delegate.webView(webView, didFinish: navigation)
            return
        }
        finishWorkItem = DispatchWorkItem { [delegate, weak self] in
            self?.finishWorkItem?.cancel()
            delegate.webView(webView, didFinish: navigation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: finishWorkItem!)
    }

    @MainActor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard finishEventsDispatchTime != .instant else {
            delegate.webView(webView, didFail: navigation, withError: error)
            return
        }
        finishWorkItem = DispatchWorkItem { [delegate, weak self] in
            self?.finishWorkItem?.cancel()
            delegate.webView(webView, didFail: navigation, withError: error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: finishWorkItem!)
    }

    @MainActor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard finishEventsDispatchTime != .instant else {
            delegate.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
            return
        }
        finishWorkItem = DispatchWorkItem { [delegate, weak self] in
            self?.finishWorkItem?.cancel()
            delegate.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: finishWorkItem!)
    }

}

private extension NSObject {
    private static let onDeinitKey = UnsafeRawPointer(bitPattern: "onDeinitKey".hashValue)!
    func onDeinit(do job: @escaping () -> Void) {
        let cancellable = AnyCancellable(job)
        objc_setAssociatedObject(self, Self.onDeinitKey, cancellable, .OBJC_ASSOCIATION_RETAIN)
    }
}

extension Data {

    static let sessionRestorationMagic = Data([0x00, 0x00, 0x00, 0x02])

    var plist: [String: Any] {
        var data = self
        if data.prefix(through: Self.sessionRestorationMagic.count - 1) == Self.sessionRestorationMagic {
            data.removeFirst(Self.sessionRestorationMagic.count)
        }
        return try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    }

    func string() -> String? {
        String(data: self, encoding: .utf8)
    }

}

extension [String: Any] {

    var plist: Data {
        try! PropertyListSerialization.data(fromPropertyList: self, format: .xml, options: 0)
    }
    var interactionStateData: Data {
        Data.sessionRestorationMagic + self.plist
    }

    subscript<T>(_ key: String, as _: T.Type) -> T? {
        get {
            self[key] as! T?
        }
        _modify {
            var value = withUnsafeMutablePointer(to: &self[key]) { ptr in
                defer {
                    ptr.pointee = nil
                }
                return ptr.pointee as! T?
            }
            yield &value
            self[key] = value
        }
    }

}

extension URL {
    var string: String {
        self.absoluteString
    }
    var separatedString: String {
        self.absoluteString.hasSuffix("/") ? self.absoluteString : self.absoluteString + "/"
    }
}
