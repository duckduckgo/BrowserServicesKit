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

    static func `for`(_ url: URL, isDesktop: Bool, privacyConfig: PrivacyConfiguration) -> String

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

        static let osVersion = " OS ([0-9_]+)"
        static let webKitVersion = #"AppleWebKit\s*\/\s*([\d.]+)"#

    }

    enum Fallback {

        static let webKitVersion = "605.1.15"
        static let safariComponent = "Safari/\(webKitVersion)"
        static let safariVersion = "14.1.2"
        static let defaultAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_5 like Mac OS X) AppleWebKit/\(webKitVersion) (KHTML, like Gecko) Mobile/15E148"

    }

}

public struct CustomUserAgent: CustomUserAgentProtocol {

    private static let safariVersion: String = { // provide mac version for this
        #if os(macOS)
            guard let range = webView.range(of: Constant.Regex.osVersion, options: .regularExpression) else { return Constant.Fallback.safariVersion } // different for mac i suppose
            let osVersion = String(webView[range])
            let versionComponents = osVersion.split(separator: "_").prefix(2)
            return versionComponents.count > 1 ? "\(versionComponents.joined(separator: "."))" : Constant.Fallback.safariVersion
        #else

        #endif
    }()
    private static let webKitVersion: String = {
        guard let range = webView.range(of: Constant.Regex.webKitVersion, options: .regularExpression) else { return Constant.Fallback.webKitVersion }
        return String(webView[range])
    }()

    static var appMajorVersionNumber: String = AppVersion.shared.majorVersionNumber
    static var webView = WKWebView().value(forKey: Constant.Key.userAgent) as? String ?? Constant.Fallback.defaultAgent // todo different fallback for mac? pad?
    private static var webViewDesktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/\(webKitVersion) (KHTML, like Gecko)"
//UIDevice.current.userInterfaceIdiom == .pad
    private static let safariComponent = "\(Constant.Prefix.safari)\(webKitVersion)"
    private static let applicationComponent = "\(Constant.Prefix.ddg)\(appMajorVersionNumber)"

    private static let versionedWebView = makeVersionedWebViewUserAgent(webViewUserAgent: webView, version: safariVersion)
    private static let versionedWebViewDesktop = makeVersionedWebViewUserAgent(webViewUserAgent: webViewDesktop, version: Constant.Fallback.safariVersion)

    private static let safari = "\(versionedWebView) \(safariComponent)"
    private static let safariDesktop = "\(versionedWebViewDesktop) \(safariComponent)"

    private static let ddg = "\(versionedWebView) \(applicationComponent) \(safariComponent)"
    private static let ddgDesktop = "\(versionedWebViewDesktop) \(applicationComponent) \(safariComponent)"

    private static let ddgNoApplication = safari
    private static let ddgNoApplicationDesktop = safariDesktop

    private static let ddgNoVersion = "\(webView) \(applicationComponent) \(safariComponent)"
    private static let ddgNoVersionDesktop = "\(webViewDesktop) \(applicationComponent) \(safariComponent)"

    private static let ddgNoApplicationAndVersion = "\(webView) \(safariComponent)"
    private static let ddgNoApplicationAndVersionDesktop = "\(webViewDesktop) \(safariComponent)"

    private static func makeVersionedWebViewUserAgent(webViewUserAgent: String, version: String) -> String {
        guard let range = webViewUserAgent.range(of: "Gecko)") else { return webViewUserAgent }
        return webViewUserAgent.replacingCharacters(in: range.upperBound..<range.upperBound, with: " \(Constant.Prefix.version)\(version)")
    }

    private static let `default` = {
        #if os(macOS)
            safari
        #else
            ddg
        #endif
    }()

    public static func `for`(_ url: URL,
                             isDesktop: Bool,
                             privacyConfig: PrivacyConfiguration) -> String {
        guard privacyConfig.isFeature(.customUserAgent, enabledForDomain: url.host) else { return isDesktop ? safariDesktop : safari }
        guard !privacyConfig.webViewDefaultSites.contains(url: url) else { return isDesktop ? webViewDesktop : webView }

        let omitApplication = privacyConfig.omitApplicationSites.contains(url: url)
        let omitVersion = privacyConfig.omitVersionSites.contains(url: url)

        switch (omitApplication, omitVersion) {
        case (true, true):
            return isDesktop ? ddgNoApplicationAndVersionDesktop : ddgNoApplicationAndVersion
        case (true, false):
            return isDesktop ? ddgNoApplicationDesktop : ddgNoApplication
        case (false, true):
            return isDesktop ? ddgNoVersionDesktop : ddgNoVersion
        default:
            return isDesktop ? ddgDesktop : ddg
        }
    }

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

    func removing(_ string: String) -> String {
        replacingOccurrences(of: string, with: "")
    }

}
