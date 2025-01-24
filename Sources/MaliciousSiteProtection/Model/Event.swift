//
//  Event.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PixelKit

public extension PixelKit {
    enum Parameters: Hashable {
        public static let clientSideHit = "clientSideHit"
        public static let category = "category"
        public static let settingToggledTo = "newState"
    }
}

public enum Event: PixelKitEventV2 {
    case errorPageShown(category: ThreatKind, clientSideHit: Bool)
    case visitSite(category: ThreatKind)
    case iframeLoaded(category: ThreatKind)
    case settingToggled(to: Bool)
    case matchesApiTimeout
    case matchesApiFailure(Error)

    public var name: String {
        switch self {
        case .errorPageShown:
            return "malicious-site-protection_error-page-shown"
        case .visitSite:
            return "malicious-site-protection_visit-site"
        case .iframeLoaded:
            return "malicious-site-protection_iframe-loaded"
        case .settingToggled:
            return "malicious-site-protection_feature-toggled"
        case .matchesApiTimeout:
            return "malicious-site-protection_client-timeout"
        case .matchesApiFailure:
            return "malicious-site-protection_matches-api-error"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .errorPageShown(category: let category, clientSideHit: let clientSideHit):
            return [
                PixelKit.Parameters.category: category.rawValue,
                PixelKit.Parameters.clientSideHit: String(clientSideHit),
            ]
        case .visitSite(category: let category),
             .iframeLoaded(category: let category):
            return [
                PixelKit.Parameters.category: category.rawValue,
            ]
        case .settingToggled(let state):
            return [
                PixelKit.Parameters.settingToggledTo: String(state)
            ]
        case .matchesApiTimeout,
             .matchesApiFailure:
            return [:]
        }
    }

    public var error: (any Error)? {
        switch self {
        case .errorPageShown:
            return nil
        case .visitSite:
            return nil
        case .iframeLoaded:
            return nil
        case .settingToggled:
            return nil
        case .matchesApiTimeout:
            return nil
        case .matchesApiFailure(let error):
            return error
        }
    }

}
