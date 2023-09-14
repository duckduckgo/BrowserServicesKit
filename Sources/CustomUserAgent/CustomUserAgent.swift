//
//  UserAgent.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import WebKit
import BrowserServicesKit
import Common


protocol CustomUserAgentProtocol {

    static func `for`(_ url: URL, isFakingDesktop: Bool, privacyConfig: PrivacyConfiguration) -> String

}

private enum Constant {

    enum Key {

        static let webViewDefaultSites = "webViewDefault"
        static let omitApplicationSites = "omitApplicationSites"
        static let omitVersionSites = "omitVersionSites"
        static let domain = "domain"
        static let userAgent = "userAgent"

    }

    enum Prefix {

        static let version = "Version/"
        static let safari = "Safari/"
        static let ddg = "DuckDuckGo/"

    }

    enum Regex {

        static let osVersion = "(?<= OS )([0-9_]+)"
        static let webKitVersion = "(?<=AppleWebKit/)([0-9_.]+)"

    }

    enum Fallback {

        static let webKitVersion = "605.1.15"
        static let safariVersion = "14.1.2"

        static let phoneWebView = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_5 like Mac OS X) AppleWebKit/\(webKitVersion) (KHTML, like Gecko) Mobile/15E148"
        static let padWebView = "Mozilla/5.0 (iPad; CPU OS 12_4 like Mac OS X) AppleWebKit/\(webKitVersion) (KHTML, like Gecko) Mobile/15E148"
        static let desktopWebView = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/\(webKitVersion) (KHTML, like Gecko)"

    }

}

enum Environment {

    case macOS
    case iOS

}

public enum CustomUserAgent: CustomUserAgentProtocol {

    @available(macOS 11, *)
    public static func configure(withSafariVersion safariVersion: String, appMajorVersion: String) {
        self.safariVersion = safariVersion
        self.appMajorVersion = appMajorVersion
    }
    @available(iOS 13, *)
    public static func configure(withAppMajorVersion appMajorVersion: String) {
        self.appMajorVersion = appMajorVersion
    }

    private static var safariVersion: String = {
        guard let range = webView.range(of: Constant.Regex.osVersion, options: .regularExpression) else { return Constant.Fallback.safariVersion }
        let osVersion = String(webView[range])
        let versionComponents = osVersion.split(separator: "_").prefix(2)
        return versionComponents.count > 1 ? "\(versionComponents.joined(separator: "."))" : Constant.Fallback.safariVersion
    }()
    private static var appMajorVersion: String = AppVersion.shared.majorVersionNumber

    private static let webKitVersion: String = {
        guard let range = webView.range(of: Constant.Regex.webKitVersion, options: .regularExpression) else { return Constant.Fallback.webKitVersion }
        return String(webView[range])
    }()

    static var webView = WKWebView().value(forKey: Constant.Key.userAgent) as? String ?? fallbackWebView
    static var currentEnvironment: Environment = {
        #if os(macOS)
            .macOS
        #else
            .iOS
        #endif
    }()

    static let fallbackWebView: String = {
        switch currentEnvironment {
        case .macOS: return Constant.Fallback.desktopWebView
        case .iOS:
            #if os(iOS)
                return UIDevice.current.userInterfaceIdiom == .pad ? Constant.Fallback.padWebView : Constant.Fallback.phoneWebView
            #else
                return ""
            #endif
        }
    }()

    private static let fakedDesktopWebView = Constant.Fallback.desktopWebView

    private static let safariComponent = "\(Constant.Prefix.safari)\(webKitVersion)"
    private static let applicationComponent = "\(Constant.Prefix.ddg)\(appMajorVersion)"
    private static let versionComponent = "\(Constant.Prefix.version)\(safariVersion)"

    private static let versionedWebView = makeVersionedWebViewUserAgent(webViewUserAgent: webView)
    private static let versionedWebViewDesktop = makeVersionedWebViewUserAgent(webViewUserAgent: fakedDesktopWebView)

    private static let safari = "\(versionedWebView) \(safariComponent)"
    private static let fakedDesktopSafari = "\(versionedWebViewDesktop) \(safariComponent)"

    private static let ddg = "\(versionedWebView) \(applicationComponent) \(safariComponent)"
    private static let fakedDesktopDDG = "\(versionedWebViewDesktop) \(applicationComponent) \(safariComponent)"

    private static let fixedSafari = ""

    // if we ever decide to introduce custom ddg user agent on macOS this is the only piece of code we should change
    private static let custom: (Bool) -> String = { isFakingDesktop in
        switch currentEnvironment {
        case .macOS: return safari
        case .iOS: return isFakingDesktop ? fakedDesktopDDG : ddg
        }
    }

    private static func makeVersionedWebViewUserAgent(webViewUserAgent: String) -> String {
        guard let range = webViewUserAgent.range(of: "Gecko)") else { return webViewUserAgent }
        return webViewUserAgent.replacingCharacters(in: range.upperBound..<range.upperBound, with: " \(versionComponent)")
    }

    @available(macOS 11, *)
    public static func `for`(_ url: URL, privacyConfig: PrivacyConfiguration) -> String {
        if let userAgent = localUserAgentConfiguration.first(where: { (regex, _) in url.absoluteString.matches(regex) })?.value {
            return userAgent
        }
        return self.for(url, isFakingDesktop: false, privacyConfig: privacyConfig)
    }

    @available(iOS 13, *)
    public static func `for`(_ url: URL,
                             isFakingDesktop: Bool,
                             privacyConfig: PrivacyConfiguration) -> String {
        guard privacyConfig.isFeature(.customUserAgent, enabledForDomain: url.host) else { return isFakingDesktop ? fakedDesktopSafari : safari }
        guard !privacyConfig.webViewDefaultSites.contains(url: url) else { return isFakingDesktop ? fakedDesktopWebView : webView }

        var custom = custom(isFakingDesktop)
        if privacyConfig.omitApplicationSites.contains(url: url) {
            custom.remove("\(applicationComponent) ")
        }
        if privacyConfig.omitVersionSites.contains(url: url) {
            custom.remove("\(versionComponent) ")
        }
        return custom
    }

    @available(macOS 11, *)
    static let localUserAgentConfiguration: KeyValuePairs<RegEx, String> = [
        // use safari when serving up PDFs from duckduckgo directly
        regex("https://duckduckgo\\.com/[^?]*\\.pdf"): safari,

        // use default WKWebView user agent for duckduckgo domain to remove CTA
        regex("https://duckduckgo\\.com/.*"): webView
    ]

}

private extension PrivacyConfiguration {

    var omitApplicationSites: [String] { extractSites(forKey: Constant.Key.omitApplicationSites) }
    var omitVersionSites: [String] { extractSites(forKey: Constant.Key.omitVersionSites) }
    var webViewDefaultSites: [String] { extractSites(forKey: Constant.Key.webViewDefaultSites) }

    private func extractSites(forKey key: String) -> [String] {
        let sites = customUserAgentSettings[key] as? [[String: String]] ?? []
        return sites.map { $0[Constant.Key.domain] ?? "" }
    }

    private var customUserAgentSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings { settings(for: .customUserAgent) }

}

private extension Array where Element == String {

    func contains(url: URL) -> Bool { contains { domain in url.isPart(ofDomain: domain) } }

}

private extension String {

    mutating func remove(_ string: String) { self = replacingOccurrences(of: string, with: "") }

}
