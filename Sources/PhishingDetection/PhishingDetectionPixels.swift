//
//  PhishingDetectionPixels.swift
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
        public static let clientSideHit = "client_side_hit"
    }
}

public enum PhishingDetectionPixels: PixelKitEventV2 {
    case errorPageShown(clientSideHit: Bool)
    case visitSite
    case iframeLoaded
    case updateTaskFailed48h(error: Error?)

    public var name: String {
        switch self {
        case .errorPageShown:
            return "phishing_detection_error-page-shown"
        case .visitSite:
            return "phishing_detection_visit-site"
        case .iframeLoaded:
            return "phishing_detection_iframe-loaded"
        case .updateTaskFailed48h:
            return "phishing_detection_update-task-failed-48h"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .errorPageShown(let clientSideHit):
            return [PixelKit.Parameters.clientSideHit: String(clientSideHit)]
        case .visitSite:
            return [:]
        case .iframeLoaded:
            return [:]
        case .updateTaskFailed48h(let error):
            return error?.pixelParameters
        }
    }

    public var error: (any Error)? {
        switch self {
        case .updateTaskFailed48h(let error):
            return error
        case .errorPageShown:
            return nil
        case .visitSite:
            return nil
        case .iframeLoaded:
            return nil
        }
    }

}
