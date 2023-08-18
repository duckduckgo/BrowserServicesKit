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
import BrowserServicesKit

protocol CustomUserAgentProtocol {

    func calculate(for url: URL, isDesktop: Bool, privacyConfig: PrivacyConfiguration) -> String?

}

private enum Constant {

    enum Key {

        static let webViewDefaultSites = "webViewDefault"
        static let omitApplicationSites = "omitApplicationSites"
        static let omitVersionSites = "omitVersionSites"
        static let domain = "domain"

    }

    enum Prefix {

        static let version = "Version/"
        static let safari = "Safari/"
        static let ddg = "DuckDuckGo/"

    }

    enum Regex {

        static let suffix = "(AppleWebKit/.*) Mobile"
        static let webKitVersion = "AppleWebKit/([^ ]+) "
        static let osVersion = " OS ([0-9_]+)"

    }

    enum Fallback {

        static let webKitVersion = "605.1.15"
        static let safariComponent = "Safari/\(webKitVersion)"
        static let versionComponent = "Version/13.1.1"
        /*perhaps should be called safari like*/static let defaultAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_5 like Mac OS X) AppleWebKit/\(webKitVersion) (KHTML, like Gecko) Mobile/15E148"
        static let desktopPrefixComponent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)"

    }

}

public struct CustomUserAgent: CustomUserAgentProtocol {

    private let webViewUserAgent: String
    private let desktopWebViewUserAgent: String

    private let versionedWebViewUserAgent: String
    private let versionedDesktopWebViewUserAgent: String

    private let applicationComponent: String
    private let safariComponent: String

    private let appMajorVersionNumber: String = "" // perhaps can be default argument for both platforms

    init(webViewUserAgent: String) {
        self.webViewUserAgent = webViewUserAgent
        desktopWebViewUserAgent = Self.makeDesktopWebViewUserAgent(originalWebViewUserAgent: webViewUserAgent)

        let versionComponent = Self.makeVersionComponent(webViewUserAgent: webViewUserAgent)
        versionedWebViewUserAgent = Self.makeVersionedWebViewUserAgent(originalWebViewUserAgent: webViewUserAgent, versionComponent: versionComponent)
        versionedDesktopWebViewUserAgent = Self.makeVersionedWebViewUserAgent(originalWebViewUserAgent: desktopWebViewUserAgent, versionComponent: versionComponent)

        applicationComponent = "\(Constant.Prefix.ddg)\(appMajorVersionNumber)"

        safariComponent = Self.makeSafariComponent(webViewUserAgent: webViewUserAgent)
    }

    private static func makeVersionComponent(webViewUserAgent: String) -> String {
        extractComponent(from: webViewUserAgent, matching: Constant.Regex.osVersion) { version in
            let versionComponents = version.split(separator: "_").prefix(2)
            return versionComponents.count > 1 ? "\(Constant.Prefix.version)\(versionComponents.joined(separator: "."))" : nil
        } ?? Constant.Fallback.versionComponent
    }

    private static func makeVersionedWebViewUserAgent(originalWebViewUserAgent: String, versionComponent: String) -> String {
        var components = originalWebViewUserAgent.split(separator: " ")
        if !components.isEmpty {
            components.insert(.init(versionComponent), at: components.endIndex - 1)
            return components.joined(separator: " ")
        }
        return originalWebViewUserAgent
    }

    private static func makeSafariComponent(webViewUserAgent: String) -> String {
        extractComponent(from: webViewUserAgent, matching: Constant.Regex.webKitVersion) { version in
            "\(Constant.Prefix.safari)\(version)"
        } ?? Constant.Fallback.safariComponent
    }

    private static func makeDesktopWebViewUserAgent(originalWebViewUserAgent: String) -> String {
        extractComponent(from: originalWebViewUserAgent, matching: Constant.Regex.suffix) { suffix in
            "\(Constant.Fallback.desktopPrefixComponent) \(suffix)"
        } ?? originalWebViewUserAgent
    }

    private static func extractComponent(from string: String, matching regexPattern: String, transform: (String) -> String?) -> String? {
        if let regex = try? NSRegularExpression(pattern: regexPattern),
           let match = regex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)),
           let range = Range(match.range(at: 1), in: string) {
            let component = String(string[range])
            return transform(component)
        }
        return nil
    }

    public func calculate(for url: URL,
                          isDesktop: Bool,
                          privacyConfig: PrivacyConfiguration /*= ContentBlocking.shared.privacyConfigurationManager.privacyConfig*/) -> String? {
        var applicationComponent: String? { privacyConfig.omitApplicationSites.contains(url: url) ? nil : self.applicationComponent }

        var webViewUserAgent: String {
            privacyConfig.omitVersionSites.contains(url: url) ?
            (isDesktop ? desktopWebViewUserAgent : self.webViewUserAgent) :
            (isDesktop ? versionedDesktopWebViewUserAgent : versionedWebViewUserAgent)
        }

        var safariUserAgent: String { "\(isDesktop ? versionedDesktopWebViewUserAgent : versionedWebViewUserAgent) \(safariComponent)" }

        guard privacyConfig.isFeature(.customUserAgent, enabledForDomain: url.host) else { return safariUserAgent }
        guard !privacyConfig.webViewDefaultSites.contains(url: url) else { return nil }

        return [webViewUserAgent, applicationComponent, safariComponent].compactMap { $0 }.joined(separator: " ")
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
