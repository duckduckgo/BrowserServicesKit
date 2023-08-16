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

protocol UserAgentProtocol {

    func agent(for url: URL, isDesktop: Bool, privacyConfig: PrivacyConfiguration) -> String

}

private enum Constant {

    enum Key {

        static let webViewDefault = "webViewDefault"
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

public struct UserAgent: UserAgentProtocol {

    private lazy var ddg: String = { "\(webViewUserAgentWithVersion) \(ddgComponent) \(safariComponent)" }()
    private lazy var noVersion: String = { "\(webViewUserAgent) \(ddgComponent) \(safariComponent)" }()
    private lazy var noApplication: String = { "\(webViewUserAgentWithVersion) \(safariComponent)" }() // safari like
    private lazy var noVersionNoApplication: String = { "\(webViewUserAgent) \(safariComponent)" }()
    private lazy var safari: String = { "\(webViewUserAgentWithVersion) \(safariComponent)" }()
    private lazy var desktop: String = {
        Self.makeDesktopAgent(fromAgent: webViewUserAgent, versionComponent: versionComponent) ??
        Self.makeDesktopAgent(fromAgent: Constant.Fallback.defaultAgent, versionComponent: versionComponent)!
    }()

    private lazy var versionComponent: String = {
        Self.extractComponent(fromAgent: webViewUserAgent, using: Constant.Regex.osVersion) { version in
            let versionComponents = version.split(separator: "_").prefix(2)
            return versionComponents.count > 1 ? "\(Constant.Prefix.version)\(versionComponents.joined(separator: "."))" : nil
        } ?? Constant.Fallback.versionComponent
    }()

    private lazy var safariComponent: String = {
        Self.extractComponent(fromAgent: webViewUserAgent, using: Constant.Regex.webKitVersion) { version in
            "\(Constant.Prefix.safari)\(version)"
        } ?? Constant.Fallback.safariComponent
    }()

    private lazy var ddgComponent: String = { "\(Constant.Prefix.ddg)\(appMajorVersionNumber)" }()

    private lazy var webViewUserAgentWithVersion: String = {
        var agentComponents = webViewUserAgent.split(separator: " ")
        guard !agentComponents.isEmpty else { return webViewUserAgent }
        agentComponents.insert(.init(versionComponent), at: agentComponents.endIndex - 1)
        return agentComponents.joined(separator: " ")
    }()

    private static func makeDesktopAgent(fromAgent agent: String,
                                         versionComponent: String) -> String? {
        extractComponent(fromAgent: agent, using: Constant.Regex.suffix) { suffix in
            "\(Constant.Fallback.desktopPrefixComponent) \(suffix) \(versionComponent)"
        }
    }

    private static func extractComponent(fromAgent agent: String, using regexPattern: String, transform: (String) -> String?) -> String? {
        if let regex = try? NSRegularExpression(pattern: regexPattern),
           let match = regex.firstMatch(in: agent, options: [], range: NSRange(agent.startIndex..., in: agent)),
           let range = Range(match.range(at: 1), in: agent) {
            let component = String(agent[range])
            return transform(component)
        }
        return nil
    }

    let webViewUserAgent: String //Constants.fallbackDefaultAgent
    let appMajorVersionNumber: String

    func agent(for url: URL, isDesktop: Bool, privacyConfig: PrivacyConfiguration /*= ContentBlocking.shared.privacyConfigurationManager.privacyConfig*/) -> String? {


        // we need to build it dynamically here for desktop purposes and what about mac, we need it too! look at impl and try to figure it out! + tests


        if !privacyConfig.isFeature(.customUserAgent, enabledForDomain: url.host) {
            return safari
        }

        if privacyConfig.webViewDefaultSites.contains(url: url) {
            return nil
        }

        if privacyConfig.omitVersionSites.contains(url: url) {
            return noVersion
        }

        if privacyConfig.omitApplicationSites.contains(url: url) {
            return safari
        }

        if privacyConfig.omitVersionSites.contains(url: url) && privacyConfig.omitApplicationSites.contains(url: url) {
            return noVersionNoApplication
        }
    }

}

private extension PrivacyConfiguration {

    var omitApplicationSites: [String] { extractSites(forKey: Constant.Key.omitApplicationSites) }
    var omitVersionSites: [String] { extractSites(forKey: Constant.Key.omitVersionSites) }
    var webViewDefaultSites: [String] { extractSites(forKey: Constant.Key.webViewDefault) }

    private func extractSites(forKey key: String) -> [String] {
        let sites = customUserAgentSettings[key] as? [[String: String]] ?? []
        return sites.map { $0[Constant.Key.domain] ?? "" }
    }

    private var customUserAgentSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings { settings(for: .customUserAgent) }

}

private extension Array where Element == String {

    func contains(url: URL) -> Bool { contains { domain in url.isPart(ofDomain: domain) } }

}
