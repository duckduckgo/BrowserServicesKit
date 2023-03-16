//
//  PrivacyFeature.swift
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

public enum PrivacyFeature: String, Feature {
    case contentBlocking
    case duckPlayer
    case fingerprintingTemporaryStorage
    case fingerprintingBattery
    case fingerprintingScreenSize
    case gpc
    case httpsUpgrade = "https"
    case autoconsent
    case clickToPlay
    case autofill
    case ampLinks
    case trackingParameters
    case customUserAgent
    case referrer
    case adClickAttribution
    case windowsWaitlist
}

public struct AutofillFeature: NestedFeature {
    public typealias SubFeatureType = Subfeature
    public static let parent: PrivacyFeature = .autofill

    public enum Subfeature: String, Feature {
        case emailProtection
        case credentialsAutofill
        case credentialsSaving
    }
}

public protocol Feature {
    var key: String { get }
}

public protocol NestedFeature: Feature {
    associatedtype SubFeatureType: Feature, RawRepresentable
    static var parent: PrivacyFeature { get }
}

extension NestedFeature {
    public var key: String {
        Self.parent.key
    }
}

extension Feature where Self: RawRepresentable, Self.RawValue == String {
    public var key: String {
        return rawValue
    }
}
