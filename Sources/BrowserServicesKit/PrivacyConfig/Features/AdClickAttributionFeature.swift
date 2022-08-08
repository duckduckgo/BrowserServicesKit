//
//  AdClickAttributionFeature.swift
//  DuckDuckGo
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
import Combine

public protocol AdClickAttributing {
    
    var isEnabled: Bool { get }
    var allowlist: [AdClickAttributionFeature.AllowlistEntry] { get }
    var navigationExpiration: Double { get }
    var totalExpiration: Double { get }
    var isHeuristicDetectionEnabled: Bool { get }
    var isDomainDetectionEnabled: Bool { get }
    
    func isMatchingAttributionFormat(_ url: URL) -> Bool
    func attributionDomainParameterName(for: URL) -> String?
}

public class AdClickAttributionFeature: AdClickAttributing {
    
    private class LinkFormats {
        
        // Map host to related link formats
        private var linkFormats: [String: [LinkFormat]]
        
        init(linkFormatsJSON: [[String: String]]) {
            var linkFormatsMap = [String: [LinkFormat]]()
            for entry in linkFormatsJSON {
                guard let urlString = entry["url"],
                      let url = URL(string: URL.URLProtocol.https.scheme + urlString),
                      let host = url.host else { continue }
                
                let linkFormat = LinkFormat(url: url,
                                            adDomainParameterName: entry["adDomainParameterName"],
                                            paramName: entry["parameterName"],
                                            paramValue: entry["parameterValue"])
                linkFormatsMap[host, default: []].append(linkFormat)
            }
            self.linkFormats = linkFormatsMap
        }
        
        func linkFormat(for url: URL) -> LinkFormat? {
            guard let domain = url.host else { return nil }
            
            for linkFormat in linkFormats[domain] ?? [] {
                if linkFormat.url.host == domain,
                   url.path == linkFormat.url.path {
                    
                    if let parameterMatching = linkFormat.adDomainParameterName,
                       (try? url.getParameter(name: parameterMatching)) != nil {
                        return linkFormat
                    } else if linkFormat.matcher?.matches(url) ?? false {
                        return linkFormat
                    }
                }
            }
            return nil
        }
    }
    
    enum Constants {
        static let linkFormatsSettingsKey = "linkFormats"
        static let allowlistSettingsKey = "allowlist"
        static let navigationExpirationSettingsKey = "navigationExpiration"
        static let totalExpirationSettingsKey = "totalExpiration"
        static let heuristicDetectionKey = "heuristicDetection"
        static let domainDetectionKey = "domainDetection"
    }
    
    private let configManager: PrivacyConfigurationManaging
    var updateCancellable: AnyCancellable?
    
    public private(set) var isEnabled = false
    private var navigationLinkFormats = LinkFormats(linkFormatsJSON: [])
    public private(set) var allowlist = [AllowlistEntry]()
    public private(set) var navigationExpiration: Double = 0
    public private(set) var totalExpiration: Double = 0
    public private(set) var isHeuristicDetectionEnabled: Bool = false
    public private(set) var isDomainDetectionEnabled: Bool = false
    
    public init(with manager: PrivacyConfigurationManaging) {
        
        configManager = manager
        
        updateCancellable = configManager.updatesPublisher.receive(on: DispatchQueue.main).sink { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.update(with: strongSelf.configManager.privacyConfig)
        }
        update(with: manager.privacyConfig)
    }
    
    public func update(with config: PrivacyConfiguration) {
        isEnabled = config.isEnabled(featureKey: .adClickAttribution)
        guard isEnabled else {
            isEnabled = false
            navigationLinkFormats = LinkFormats(linkFormatsJSON: [])
            allowlist = []
            isHeuristicDetectionEnabled = false
            isDomainDetectionEnabled = false
            return
        }
        
        let settings = config.settings(for: .adClickAttribution)
        
        let linkFormats = settings[Constants.linkFormatsSettingsKey] as? [[String: String]] ?? []
        navigationLinkFormats = LinkFormats(linkFormatsJSON: linkFormats)
        
        if let allowlist = settings[Constants.allowlistSettingsKey] as? [[String: String]] {
            self.allowlist = allowlist.compactMap({ entry in
                guard let host = entry["host"], let blocklistEntry = entry["blocklistEntry"] else { return nil }
                return AllowlistEntry(entity: blocklistEntry, host: host)
            })
        } else {
            self.allowlist = []
        }
        
        if let navigationExpiration = settings[Constants.navigationExpirationSettingsKey] as? NSNumber {
            self.navigationExpiration = navigationExpiration.doubleValue
        } else {
            navigationExpiration = 1800
        }
        
        if let totalExpiration = settings[Constants.totalExpirationSettingsKey] as? NSNumber {
            self.totalExpiration = totalExpiration.doubleValue
        } else {
            totalExpiration = 604800
        }
        
        isHeuristicDetectionEnabled = (settings[Constants.heuristicDetectionKey] as? String) == PrivacyConfigurationData.State.enabled
        isDomainDetectionEnabled = (settings[Constants.domainDetectionKey] as? String) == PrivacyConfigurationData.State.enabled
    }
    
    public func isMatchingAttributionFormat(_ url: URL) -> Bool {
        navigationLinkFormats.linkFormat(for: url) != nil
    }
    
    public func attributionDomainParameterName(for url: URL) -> String? {
        navigationLinkFormats.linkFormat(for: url)?.adDomainParameterName
    }

    
    public struct AllowlistEntry {
        public let entity: String
        public let host: String
        
        public init(entity: String, host: String) {
            self.entity = entity
            self.host = host
        }
    }
    
    private struct LinkFormat {
        let url: URL
        let adDomainParameterName: String?
        let matcher: ParamMatching?
        
        init(url: URL,
             adDomainParameterName: String?,
             paramName: String?,
             paramValue: String?) {
            
            self.url = url
            self.adDomainParameterName = adDomainParameterName
            
            if let parameterName = paramName {
                if let parameterValue = paramValue {
                    matcher = ParamNameAndValueMatching(name: parameterName, value: parameterValue)
                } else {
                    matcher = ParamNameMatching(name: parameterName)
                }
            } else {
                matcher = nil
            }
        }
    }
    
    private class ParamMatching {
        func matches(_ url: URL) -> Bool {
            assertionFailure("This is abstract method")
            return false
        }
    }
    
    private class ParamNameMatching: ParamMatching {
        
        private let paramName: String
        
        init(name: String) {
            paramName = name
        }
        
        override func matches(_ url: URL) -> Bool {
            return (try? url.getParameter(name: paramName)) != nil
        }
    }
    
    private class ParamNameAndValueMatching: ParamMatching {
        private let paramName: String
        private let paramValue: String
        
        init(name: String, value: String) {
            paramName = name
            paramValue = value
        }
        
        override func matches(_ url: URL) -> Bool {
            guard let value = (try? url.getParameter(name: paramName)) else {
                return false
            }
            return value == paramValue
        }
    }
}
