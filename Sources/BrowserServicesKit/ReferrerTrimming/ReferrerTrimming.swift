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

public struct ReferrerTrimming {
    
    struct Constants {
        static let headerName = "Referer"
        static let policyName = "Referrer-Policy"
    }
    
    private let privacyManager: PrivacyConfigurationManager
    private var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }
    
    init(privacyManager: PrivacyConfigurationManager) {
        self.privacyManager = privacyManager
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
        
        guard let referrerHeader = request.value(forHTTPHeaderField: Constants.headerName),
            let referrerUrl = URL(string: referrerHeader), referrerUrl.host != nil else {
            return nil
        }
        
        // TODO: Entity Checks
        
        // TODO: Tracker Checks
        
        
        request.setValue("\(referrerUrl.scheme ?? "http")://\(referrerUrl.host!)", forHTTPHeaderField: Constants.headerName)
        
        return request
    }
}
