//
//  PrivacyProSubscription.swift
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

public struct PrivacyProSubscription: Codable, Equatable, CustomDebugStringConvertible {
    public let productId: String
    public let name: String
    public let billingPeriod: PrivacyProSubscription.BillingPeriod
    public let startedAt: Date
    public let expiresOrRenewsAt: Date
    public let platform: PrivacyProSubscription.Platform
    public let status: Status

    public enum BillingPeriod: String, Codable {
        case monthly = "Monthly"
        case yearly = "Yearly"
        case unknown

        public init(from decoder: Decoder) throws {
            self = try Self(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
        }
    }

    public enum Platform: String, Codable {
        case apple, google, stripe
        case unknown

        public init(from decoder: Decoder) throws {
            self = try Self(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
        }
    }

    public enum Status: String, Codable {
        case autoRenewable = "Auto-Renewable"
        case notAutoRenewable = "Not Auto-Renewable"
        case gracePeriod = "Grace Period"
        case inactive = "Inactive"
        case expired = "Expired"
        case unknown

        public init(from decoder: Decoder) throws {
            self = try Self(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
        }
    }

    public var isActive: Bool {
        status != .expired && status != .inactive
    }

    public var debugDescription: String {
        return """
        Subscription:
        - Product ID: \(productId)
        - Name: \(name)
        - Billing Period: \(billingPeriod.rawValue)
        - Started At: \(formatDate(startedAt))
        - Expires/Renews At: \(formatDate(expiresOrRenewsAt))
        - Platform: \(platform.rawValue)
        - Status: \(status.rawValue)
        """
    }

    private func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.timeZone = TimeZone.current
        return dateFormatter.string(from: date)
    }
}
