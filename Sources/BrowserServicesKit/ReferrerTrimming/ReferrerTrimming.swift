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

public class ReferrerTrimming {
    
    struct Constants {
        static let headerName = "Referer"
        static let policyName = "Referrer-Policy"
    }
    
    public enum TrimmingState {
        case idle
        case navigating(destination: URL)
    }
    
    private let privacyManager: PrivacyConfigurationManager
    private var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }
    
    private let contentBlockingManager: ContentBlockerRulesManager
    
    private var state: TrimmingState = .idle
    
    private var tld: TLD
    
    public init(privacyManager: PrivacyConfigurationManager,
                contentBlockingManager: ContentBlockerRulesManager,
                tld: TLD) {
        self.privacyManager = privacyManager
        self.contentBlockingManager = contentBlockingManager
        self.tld = tld
    }
    
    public func onBeginNavigation(to destination: URL?) {
        guard let destination = destination else {
            return
        }
        
        state = .navigating(destination: destination)
    }
    
    public func onFinishNavigation() {
        state = .idle
    }
    
    public func onFailedNavigation() {
        state = .idle
    }
    
    func getTrimmedReferrer(originUrl: URL, destUrl: URL, referrerUrl: URL?, trackerData: TrackerData) -> String? {
        func isSameEntity(a: Entity?, b: Entity?) -> Bool {
            if a == nil && b == nil {
                return !originUrl.isThirdParty(to: destUrl, tld: tld)
            }
            
            return a?.displayName == b?.displayName
        }
        
        guard privacyConfig.isFeature(.referrer, enabledForDomain: originUrl.host!),
              privacyConfig.isFeature(.referrer, enabledForDomain: destUrl.host!) else {
            return nil
        }
        guard let referrerUrl = referrerUrl else {
            return nil
        }
        
        guard originUrl.host != nil, originUrl.scheme != nil else {
            return nil
        }
        guard destUrl.host != nil, destUrl.scheme != nil else {
            return nil
        }
        
        let referEntity = trackerData.findEntity(forHost: originUrl.host!)
        let destEntity = trackerData.findEntity(forHost: destUrl.host!)
        
        var newReferrer: String?
        if !isSameEntity(a: referEntity, b: destEntity) {
            newReferrer = "\(referrerUrl.scheme!)://\(referrerUrl.host!)/"
        }

        if trackerData.findTracker(forUrl: destUrl.absoluteString) != nil && !isSameEntity(a: referEntity, b: destEntity) {
            newReferrer = "\(referrerUrl.scheme!)://\(tld.eTLDplus1(referrerUrl.host) ?? referrerUrl.host!)/"
        }
        
        return newReferrer
    }
    
    public func trimReferrer(forNavigation navigationAction: WKNavigationAction, originUrl: URL?) -> URLRequest? {
        var request = navigationAction.request
        guard let originUrl = originUrl else {
            return nil
        }
        guard let destUrl = request.url else {
            return nil
        }
        switch state {
        case let .navigating(trimmingUrl):
            if trimmingUrl != destUrl {
                // If mainFrameUrl is set and is different from destinationURL we will assume this is a redirect
                // We do not rewrite redirects due to breakage concerns
                return nil
            }
        case .idle:
            onBeginNavigation(to: destUrl)
        }
        
        guard let trackerData = contentBlockingManager.currentMainRules?.trackerData else {
            return nil
        }
        
        guard let referrerHeader = request.value(forHTTPHeaderField: Constants.headerName) else {
            return nil
        }
        
        if let newReferrer = getTrimmedReferrer(originUrl: originUrl,
                                                destUrl: destUrl,
                                                referrerUrl: URL(string: referrerHeader) ?? nil,
                                                trackerData: trackerData) {
            request.setValue(newReferrer, forHTTPHeaderField: Constants.headerName)
            return request
        }
        
        return nil
    }
}
