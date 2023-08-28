//
//  PrivacyConfigurationData.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

// swiftlint:disable nesting
public struct PrivacyConfigurationData {

    public typealias FeatureName = String
    public typealias TrackerAllowlistData = [String: [TrackerAllowlist.Entry]]

    enum CodingKeys: String {
        case features
        case unprotectedTemporary
        case trackerAllowlist
    }

    public struct State {
        static public let disabled = "disabled"
        static public let `internal` = "internal"
        static public let enabled = "enabled"
    }

    public let features: [FeatureName: PrivacyFeature]
    public let trackerAllowlist: TrackerAllowlist
    public let unprotectedTemporary: [ExceptionEntry]

    public init(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw PrivacyConfigurationManager.ParsingError.dataMismatch
        }
        self = .init(json: json)
    }

    internal init(json: [String: Any]) {

        if let tempListData = json[CodingKeys.unprotectedTemporary.rawValue] as? [[String: String]] {
            unprotectedTemporary = tempListData.compactMap({ ExceptionEntry(json: $0) })
        } else {
            unprotectedTemporary = []
        }

        if var featuresData = json[CodingKeys.features.rawValue] as? [String: Any] {
            var features = [FeatureName: PrivacyFeature]()

            // Allowlist entry does not follow the usual feature structure - process it first
            if let allowlistEntry = featuresData[CodingKeys.trackerAllowlist.rawValue] as? [String: Any] {
                if let allowlist = TrackerAllowlist(json: allowlistEntry) {
                    self.trackerAllowlist = allowlist
                } else {
                    self.trackerAllowlist = TrackerAllowlist(entries: [:], state: State.disabled)
                }
                featuresData.removeValue(forKey: CodingKeys.trackerAllowlist.rawValue)
            } else {
                self.trackerAllowlist = TrackerAllowlist(entries: [:], state: State.disabled)
            }

            for featureEntry in featuresData {

                guard let featureData = featureEntry.value as? [String: Any],
                      let feature = PrivacyFeature(json: featureData) else { continue }
                features[featureEntry.key] = feature
            }
            self.features = features
        } else {
            self.features = [:]
            self.trackerAllowlist = TrackerAllowlist(entries: [:], state: State.disabled)
        }
    }

    public init(features: [FeatureName: PrivacyFeature],
                unprotectedTemporary: [ExceptionEntry],
                trackerAllowlist: TrackerAllowlistData) {
        self.features = features
        self.unprotectedTemporary = unprotectedTemporary
        self.trackerAllowlist = TrackerAllowlist(entries: trackerAllowlist, state: State.enabled)
    }

    public class PrivacyFeature {
        public typealias FeatureState = String
        public typealias ExceptionList = [ExceptionEntry]
        public typealias FeatureSettings = [String: Any]
        public typealias Features = [String: Feature]
        public typealias FeatureSupportedVersion = String

        enum CodingKeys: String {
            case state
            case exceptions
            case settings
            case features
            case minSupportedVersion
            case hash
        }

        public struct Feature {
            enum CodingKeys: String {
                case state
                case minSupportedVersion
                case rollout
            }

            public struct Rollout: Hashable {
                enum CodingKeys: String {
                    case steps
                }

                public let steps: [RolloutStep]

                public init(json: [String: Any]) {
                    var rolloutSteps = [RolloutStep]()
                    if let steps = json[CodingKeys.steps.rawValue] as? [[String: Any]] {
                        for step in steps {
                            rolloutSteps.append(RolloutStep(json: step))
                        }
                    }

                    self.steps = rolloutSteps
                }
            }

            public struct RolloutStep: Hashable {
                enum CodingKeys: String {
                    case percent
                }

                public let percent: Double
                
                public init(json: [String: Any]) {
                    self.percent = json[CodingKeys.percent.rawValue] as? Double ?? 0
                }
            }
            
            public let state: FeatureState
            public let minSupportedVersion: FeatureSupportedVersion?
            public let rollout: Rollout?

            public init?(json: [String: Any]) {
                guard let state = json[CodingKeys.state.rawValue] as? String else {
                    return nil
                }

                self.state = state
                self.minSupportedVersion = json[CodingKeys.minSupportedVersion.rawValue] as? String

                if let rollout = json[CodingKeys.rollout.rawValue] as? [String: Any] {
                    self.rollout = Rollout(json: rollout)
                } else {
                    self.rollout = nil
                }
            }
        }

        public let state: FeatureState
        public let exceptions: ExceptionList
        public let settings: FeatureSettings
        public let features: Features
        public let minSupportedVersion: FeatureSupportedVersion?
        public let hash: String?

        public init?(json: [String: Any]) {
            guard let state = json[CodingKeys.state.rawValue] as? String else { return nil }
            self.state = state

            if let exceptionsData = json[CodingKeys.exceptions.rawValue] as? [[String: String]] {
                self.exceptions = exceptionsData.compactMap({ ExceptionEntry(json: $0) })
            } else {
                self.exceptions = []
            }

            self.settings = (json[CodingKeys.settings.rawValue] as? [String: Any]) ?? [:]

            var features = [String: Feature]()
            if let featuresDict = json[CodingKeys.features.rawValue] as? [String: [String: Any]] {
                for (key, value) in featuresDict {
                    features[key] = Feature(json: value)
                }
            }
            self.features = features
            self.minSupportedVersion = json[CodingKeys.minSupportedVersion.rawValue] as? String
            self.hash = json[CodingKeys.hash.rawValue] as? String
        }

        public init(state: FeatureState,
                    exceptions: [ExceptionEntry],
                    settings: [String: Any] = [:],
                    features: Features = [:],
                    minSupportedVersion: String? = nil,
                    hash: String? = nil) {
            self.state = state
            self.exceptions = exceptions
            self.settings = settings
            self.minSupportedVersion = minSupportedVersion
            self.features = features
            self.hash = hash
        }
    }

    public class TrackerAllowlist: PrivacyFeature {

        public struct Entry: Encodable {

            public let rule: String
            public let domains: [String]

            public init(rule: String, domains: [String]) {
                self.rule = rule
                self.domains = domains
            }
        }

        public private(set) var entries: TrackerAllowlistData

        public override init?(json: [String: Any]) {
            self.entries = [:]
            super.init(json: json)

            guard self.state != State.disabled else { return }

            var entries = [String: [Entry]]()

            let settings = (json[PrivacyFeature.CodingKeys.settings.rawValue] as? [String: Any]) ?? [:]

            if let trackers = settings["allowlistedTrackers"] as? [String: [String: [Any]]] {
                for (trackerDomain, trackerRules) in trackers {
                    if let rules = trackerRules["rules"] as? [ [String: Any] ] {
                        entries[trackerDomain] = rules.compactMap { ruleDict -> Entry? in
                            guard let rule = ruleDict["rule"] as? String, let domains = ruleDict["domains"] as? [String] else { return nil }

                            return Entry(rule: rule, domains: domains)
                        }
                    }
                }
            }

            self.entries = entries
        }

        public init(entries: [String: [Entry]], state: FeatureState) {
            self.entries = entries

            super.init(state: state, exceptions: [])
        }
    }

    public struct ExceptionEntry {
        public typealias ExcludedDomain = String
        public typealias ExclusionReason = String

        enum CodingKeys: String {
            case domain
            case reason
        }

        public let domain: ExcludedDomain
        public let reason: ExclusionReason?

        public init?(json: [String: String]) {
            guard let domain = json[CodingKeys.domain.rawValue] else { return nil }
            self.init(domain: domain, reason: json[CodingKeys.reason.rawValue])
        }

        public init(domain: String, reason: String?) {
            self.domain = domain
            self.reason = reason
        }
    }
}
// swiftlint:enable nesting
