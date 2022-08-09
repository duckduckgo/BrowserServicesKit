//
//  ReferrerTrimming.swift
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
import WebKit
import TrackerRadarKit

public struct ReferrerTrimming {
    
    struct Constants {
        static let headerName = "Referer"
        static let policyName = "Referrer-Policy"
    }
    
    private let privacyManager: PrivacyConfigurationManager
    private var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }
    
    private let contentBlockingManager: ContentBlockerRulesManager
    
    private var mainFrameUrl: URL?
    
    init(privacyManager: PrivacyConfigurationManager,
         contentBlockingManager: ContentBlockerRulesManager) {
        self.privacyManager = privacyManager
        self.contentBlockingManager = contentBlockingManager
    }
    
    public mutating func setMainFrameUrl(_ url: URL?) {
        mainFrameUrl = url
    }
    
    func trimHostToETLD(host: String) -> String {
        guard !host.isEmpty else {
            return host
        }
        
        var newHost = host
        while newHost.contains(".") {
            let comps = newHost.split(separator: ".").dropFirst()
            newHost = comps.joined(separator: ".")
        }
        
        return newHost
    }
    
    func trimReferrer(forNavigation navigationAction: WKNavigationAction) -> URLRequest? {
        var request = navigationAction.request
        guard let originUrl = navigationAction.sourceFrame.webView?.url,
              privacyConfig.isFeature(.referrer, enabledForDomain: originUrl.host) else {
            return nil
        }
        guard let destUrl = request.url,
              privacyConfig.isFeature(.referrer, enabledForDomain: destUrl.host) else {
            return nil
        }
        if let mainFrameUrl = mainFrameUrl, destUrl != mainFrameUrl {
            // If mainFrameUrl is set and is different from destinationURL we will assume this is a redirect
            // We do not rewrite redirects due to breakage concerns
            return nil
        }
        
        guard let referrerHeader = request.value(forHTTPHeaderField: Constants.headerName),
            let referrerUrl = URL(string: referrerHeader), referrerUrl.host != nil else {
            return nil
        }
        
        guard let trackerData = contentBlockingManager.currentTDSRules?.trackerData else {
            return nil
        }
        
        let referEntity = trackerData.findEntity(forHost: originUrl.host ?? "")
        let destEntity = trackerData.findEntity(forHost: destUrl.host ?? "")
        if referEntity?.displayName != destEntity?.displayName {
            request.setValue("\(referrerUrl.scheme ?? "http")://\(referrerUrl.host!)", forHTTPHeaderField: Constants.headerName)
        }

        if trackerData.findTracker(forUrl: destUrl.absoluteString) != nil {
            request.setValue("\(referrerUrl.scheme ?? "http")://\(trimHostToETLD(host: referrerUrl.host!))", forHTTPHeaderField: Constants.headerName)
        }
        
        return request
    }
}
