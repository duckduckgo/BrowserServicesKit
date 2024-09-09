//
//  PrivacyInfo.swift
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
import TrackerRadarKit
import Common

public protocol SecurityTrust { }
extension SecTrust: SecurityTrust {}

public final class PrivacyInfo {

    public private(set) var url: URL
    private(set) var parentEntity: Entity?

    @Published public var trackerInfo: TrackerInfo
    @Published private(set) var protectionStatus: ProtectionStatus
    @Published public var serverTrust: SecurityTrust?
    @Published public var connectionUpgradedTo: URL?
    @Published public var cookieConsentManaged: CookieConsentInfo?
    @Published public var isPhishing: Bool
    @Published public var isSpecialErrorPageVisible: Bool = false

    public init(url: URL, parentEntity: Entity?, protectionStatus: ProtectionStatus, isPhishing: Bool = false) {
        self.url = url
        self.parentEntity = parentEntity
        self.protectionStatus = protectionStatus
        self.isPhishing = isPhishing

        trackerInfo = TrackerInfo()
    }

    public var https: Bool {
        return url.isHttps
    }

    public var domain: String? {
        return url.host
    }

    public func isFor(_ url: URL?) -> Bool {
        return self.url.host == url?.host
    }
}
