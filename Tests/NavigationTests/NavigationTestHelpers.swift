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

import Foundation
import Navigation
import WebKit
import Common

extension NavigationEvent {

    static func navigationAction(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, _ isUserInitiated: NavigationAction.UserInitiated? = nil, src: FrameInfo, targ: FrameInfo? = nil, _ shouldDownload: NavigationAction.ShouldDownload? = nil) -> NavigationEvent {
        .navigationAction(.init(request, navigationType, from: currentHistoryItemIdentity, isUserInitiated, src: src, targ: targ, shouldDownload))
    }
    
    static func response(_ nav: Nav) -> NavigationEvent {
        .navigationResponse(.navigation(nav))
    }

    func encoded(urls: Any, webView: WKWebView, dataSource: Any) -> String {
        let v = { () -> String in
            switch self {
            case .navigationAction(let arg, let arg2):
                if let prefs = arg2.encoded() {
                    return ".navigationAction(\(arg.encoded(urls: urls, webView: webView)), \(prefs))"
                } else {
                    return ".navigationAction" + arg.encoded(urls: urls, webView: webView).dropping(prefix: ".init")
                }
            case .willCancel(let arg, let arg2):
                return ".willCancel(\(arg.encoded(urls: urls, webView: webView))\(arg2 == .none ? "" : "," + arg2.encoded(urls: urls)))"
            case .didCancel(let arg, let arg2):
                return ".didCancel(\(arg.encoded(urls: urls, webView: webView))\(arg2 == .none ? "" : "," + arg2.encoded(urls: urls)))"
            case .navActionBecameDownload(let arg, let arg2):
                return "navActionBecameDownload(\(arg.encoded(urls: urls, webView: webView)), \(urlConst(for: arg2, in: urls)!))"
            case .willStart(let arg):
                return ".willStart(\(arg))"
            case .didStart(let arg):
                return ".didStart(\(arg.encoded(urls: urls, dataSource: dataSource)))"
            case .didReceiveAuthenticationChallenge(let arg, let arg2):
                return ".didReceiveAuthenticationChallenge(\(arg.encoded()), \(arg2?.encoded(urls: urls, dataSource: dataSource) ?? "nil"))"
            case .navigationResponse(.response(let resp)):
                return ".navigationResponse(\(resp.encoded(urls: urls, dataSource: dataSource)))"
            case .navigationResponse(.navigation(let nav)):
                return ".response(\(nav.encoded(urls: urls, dataSource: dataSource)))"

            case .navResponseBecameDownload(let arg, let arg2):
                return ".navResponseBecameDownload(\(arg), \(urlConst(for: arg2, in: urls)!))"
            case .didCommit(let arg):
                return ".didCommit(\(arg.encoded(urls: urls, dataSource: dataSource)))"
            case .didReceiveRedirect(let arg, let arg2):
                return ".didReceiveRedirect(\(arg.encoded(urls: urls, dataSource: dataSource)), \(arg2))"
            case .didFinish(let arg):
                return ".didFinish(\(arg.encoded(urls: urls, dataSource: dataSource)))"
            case .didFail(let arg, let arg2):
                return ".didFail(\(arg.encoded(urls: urls, dataSource: dataSource)), \(arg2))"
            case .didTerminate(let arg):
                return arg != nil ? ".didTerminate(\(arg!.encoded(urls: urls, dataSource: dataSource)))" : ".terminated"
            }
        }().replacing(regex: "\\s\\s+", with: "")

        return v.replacingOccurrences(of: "  ", with: " ").replacing(regex: "\\s*,\\s*", with: ", ").replacing(regex: "\\s*\\+\\s*", with: " + ").replacing(regex: "\\s+\\)", with: ")")
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
    var navigationActionIdx: Int
    var state: NavigationState
    var isCommitted: Bool = false
    var didReceiveAuthenticationChallenge: Bool = false

    enum IsCommitted {
        case committed
    }
    enum DidReceiveAuthenticationChallenge {
        case gotAuth
    }
    init(action navigationActionIdx: Int, _ state: NavigationState, _ isCommitted: IsCommitted? = nil, _ didReceiveAuthenticationChallenge: DidReceiveAuthenticationChallenge? = nil) {
        self.navigationActionIdx = navigationActionIdx
        self.state = state
        self.isCommitted = isCommitted != nil
        self.didReceiveAuthenticationChallenge = didReceiveAuthenticationChallenge != nil
    }
    init(act navigationActionIdx: Int, _ navigation: Navigation) {
        self.navigationActionIdx = navigationActionIdx
        self.state = navigation.state
        self.isCommitted = navigation.isCommitted
        self.didReceiveAuthenticationChallenge = navigation.didReceiveAuthenticationChallenge
    }

    func encoded(urls: Any, dataSource: Any) -> String {
        "Nav(action: \(navigationActionIdx), \(state.encoded(urls: urls, dataSource: dataSource)) \(isCommitted ? ", .committed" : (didReceiveAuthenticationChallenge ? ", nil" : "")) \(didReceiveAuthenticationChallenge ? ", .gotAuth" : ""))"
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

    func encoded(urls: Any, dataSource: Any) -> String {
        switch self {
        case .expected:
            return ".expected"
        case .started:
            return ".started"
        case .redirected:
            return ".redirected"
        case .responseReceived(let resp):
            return "." + resp.encoded(urls: urls, dataSource: dataSource)
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

    static func resp(_ url: URL, status: Int, mime: String? = "text/html", _ length: Int = -1, _ encoding: String? = nil, headers: [String: String] = .default) -> NavigationResponse {
        var headers = headers
        if length >= 0 {
            headers["Content-Length"] = String(length)
        }
        if let encoding {
            headers["Content-Encoding"] = encoding
        }
        let response = MockHTTPURLResponse(url: url, statusCode: status, mime: mime, httpVersion: nil, headerFields: headers)!
        return self.init(response: response, isForMainFrame: true, canShowMIMEType: true)
    }
    func encoded(urls: Any, dataSource: Any) -> String {
        if !canShowMIMEType || !isForMainFrame {
            return ".resp(\(response.encoded(urls: urls, dataSource: dataSource))\(isForMainFrame ? "" : ".nonMain")\(canShowMIMEType ? "" : ".cantShow"))"
        } else {
            return response.encoded(urls: urls, dataSource: dataSource)
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
    init?(url: URL, statusCode: Int, mime: String?, httpVersion: String? = nil, headerFields: [String : String]?) {
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
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)",
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
    func encoded(urls: Any, dataSource: Any) -> String {
        var headers = ""
        let defaultHeaders = [String: String].default
        var headerFields = (self as? HTTPURLResponse)?.allHeaderFields as? [String: String] ?? [:]
        headerFields["Content-Length"] = nil
        if !(self is HTTPURLResponse) || headerFields == defaultHeaders {
            headers = ""
        } else if (self as? HTTPURLResponse)?.allHeaderFields != nil {
            if Set(headerFields.keys).intersection(defaultHeaders.keys).count == defaultHeaders.count {
                headers = ", headers: .default + " + headerFields.filter { $0.value != defaultHeaders[$0.key] }.encoded()
            } else {
                headers = ", headers: " + headerFields.encoded()
            }
        } else {
            headers = ", headers: nil"
        }

        return """
        resp(
            \(urlConst(for: self.url!, in: urls)!),
            \((self as? HTTPURLResponse)?.statusCode != 200 ? "status: " + ((self as? HTTPURLResponse).map { String($0.statusCode) } ?? "nil") + "," : "")
            \(mimeType != "text/html" ? "mime: \"\(mimeType ?? "nil")\"," : "")
            \(expectedContentLength != -1 ? "\(dataConst(forLength: expectedContentLength, in: dataSource))" + (textEncodingName != nil ? "," : "") : "")
            \(textEncodingName != nil ? "\"\(textEncodingName!)\"" : "")
            \(headers)
        """.trimmingWhitespace().dropping(suffix: ",") + ")"
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
    func encoded(urls: Any) -> String {
        switch self {
        case .none:
            return ""
        case .taskCancelled:
            return ".cancelled"
        case .redirect(let req):
            return ".redir(\(urlConst(for: req.url!, in: urls)!))"
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
    func encoded() -> String {
        if self.isEmpty { return "[:]" }
        var result = "["
        for (idx, item) in self.enumerated() {
            if idx > 0 {
                result.append(",\n")
            }
            result.append("\"\(item.key)\": \"\(item.value)\"")
        }
        result.append("]")
        return result
    }

    static func +(lhs: Self, rhs: Self) -> Self {
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
    init(_ request: URLRequest, _ navigationType: NavigationType, from currentHistoryItemIdentity: HistoryItemIdentity? = nil, _ isUserInitiated: UserInitiated? = nil, src: FrameInfo, targ: FrameInfo? = nil, _ shouldDownload: ShouldDownload? = nil) {
        self.init(request: request, navigationType: navigationType, currentHistoryItemIdentity: currentHistoryItemIdentity, isUserInitiated: isUserInitiated != nil, sourceFrame: src, targetFrame: targ ?? src, shouldDownload: shouldDownload != nil)
    }
    func encoded(urls: Any, webView: WKWebView) -> String {
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
                headers = ", defaultHeaders + " + headerFields.filter { $0.value != defaultHeaders[$0.key] }.encoded()
            } else {
                headers = ", " + headerFields.encoded()
            }
        } else {
            headers = ", nil"
        }
        return """
        .init(
            req(\(urlConst(for: url, in: urls)!)\(headers)),
            \(navigationType.encoded(with: urls, webView: webView)),
            \(fromHistoryItemIdentity != nil ? "from: " + fromHistoryItemIdentity!.encoded(with: webView) + "," : "")
            \(isUserInitiated)
            src: \(sourceFrame.encoded(urls: urls)),
            \(targetFrame == sourceFrame  ? "" : "targ: " + targetFrame.encoded(urls: urls) + ",")
            \(shouldDownload ? ".shouldDownload," : "")
        """.trimmingWhitespace().dropping(suffix: ",") + ")"
    }
}

extension FrameInfo {
    func encoded(urls: Any) -> String {
        let secOrigin = (securityOrigin == url.securityOrigin ? "" : ", secOrigin: " + securityOrigin.encoded(urls: urls))
        if self.isMainFrame {
            return "main(" + (url.isEmpty ? "" : urlConst(for: url, in: urls)!) + secOrigin + ")"
        } else {
            return "frame(\(identity.handle), \(urlConst(for: url, in: urls)!)\(secOrigin))"
        }
    }
}

extension SecurityOrigin: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String
    public init(stringLiteral: String) {
        self = URL(string: stringLiteral)!.securityOrigin
    }

    func encoded(urls: Any) -> String {
        let url = URL(string: self.protocol + "://" + self.host + (port > 0 ? ":\(port)" : ""))!
        if let const = urlConst(for: url, in: urls) {
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

    func encoded(with urls: Any, webView: WKWebView) -> String {
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
        case .redirect(let redirect):
            return ".redirect(\(redirect.encoded(with: urls, webView: webView)))"
        case .sessionRestoration:
            return ".restore"
        case .other:
            return ".other"
        case .custom(let userInfo):
            return "<##custom: \(userInfo.debugDescription)>"
        }
    }
}
extension Redirect {
    init(_ type: RedirectType, _ history: [RedirectHistoryItem] = [], _ initial: InitialNavigationType) {
        self.init(type: type, history: history, initialNavigationType: initial)
    }
    init(_ type: RedirectType, _ historyItem: RedirectHistoryItem, _ initial: InitialNavigationType) {
        self.init(type: type, history: [historyItem], initialNavigationType: initial)
    }
    func encoded(with urls: Any, webView: WKWebView) -> String {
        """
        .init(
            \(type.encoded()),
            \(history.isEmpty ? "" : history.encoded(with: urls, webView: webView) + ",")
            \(initialNavigationType.encoded())
        )
        """
    }
}

extension InitialNavigationType {
    static var link = InitialNavigationType.linkActivated
    static func backForw(_ dist: Int) -> NavigationType { .backForward(distance: dist) }
    static var form = NavigationType.formSubmitted
    static var formRe = NavigationType.formResubmitted
    static var restore = NavigationType.sessionRestoration

    func encoded() -> String {
        switch self {
        case .linkActivated:
            return ".link"
        case .backForward(distance: let distance):
            return ".backForw(\(distance))"
        case .reload:
            return ".reload"
        case .formSubmitted:
            return ".form"
        case .formResubmitted:
            return ".formRe"
        case .sessionRestoration:
            return ".restore"
        case .other:
            return ".other"
        case .custom(let userInfo):
            return "<##custom: \(userInfo.debugDescription)>"
        }
    }
}

extension Array where Element == RedirectHistoryItem {
    func encoded(with urls: Any, webView: WKWebView) -> String {
        if count == 1 { return self[0].encoded(with: urls, webView: webView) }
        var result = "[\n"
        for (idx, item) in self.enumerated() {
            if idx > 0 {
                result.append(",\n")
            }
            result.append(item.encoded(with: urls, webView: webView))
        }
        result.append("]")
        return result
    }
}
extension RedirectHistoryItem {
    init(_ url: URL, _ type: RedirectType? = nil, from: HistoryItemIdentity? = nil) {
        self.init(identifier: 0, url: url, type: type, fromHistoryItemIdentity: from)
    }
    init(_ url: String, _ type: RedirectType? = nil, from: HistoryItemIdentity? = nil) {
        self.init(URL(string: url)!, type, from: from)
    }
    func encoded(with urls: Any, webView: WKWebView) -> String {
        ".init(\(urlConst(for: url, in: urls)!) \(type != nil ? "," + type!.encoded() : "") \(fromHistoryItemIdentity != nil ? ", from: \(fromHistoryItemIdentity!.encoded(with: webView))" : ""))"
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
        }
    }
}
extension HistoryItemIdentity {
    func encoded(with webView: WKWebView) -> String {
        "webView.item(at: \(webView.getDistance(from: self)!))"
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
    func item(at idx: Int) -> HistoryItemIdentity {
        HistoryItemIdentity(self.backForwardList.item(at: idx)!)
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

    func encoded(with urls: Any, webView: WKWebView, dataSource: Any) -> String {
        var result = "[\n"
        for (idx, item) in self.enumerated() {
            if idx > 0 {
                result.append(",\n")
            }
            result.append("  " + item.encoded(urls: urls, webView: webView, dataSource: dataSource))
        }
        result.append("\n]")
        return result
    }

}
