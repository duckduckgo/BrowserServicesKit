//
//  VPNTunnelStartPixelHandler.swift
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

import Common
import Foundation
import PixelKit

/// This class handles firing the tunnel start attempts.
///
/// The reason this logic is contained here, is that we were getting flooded by attempt pixels when an unattended system kept failing with
/// on-demand enabled.  This class aims to confine these pixels to "sessions" of attempts, so to speak.
///
final class VPNTunnelStartPixelHandler {

    typealias Event = PacketTunnelProvider.Event
    typealias Step = PacketTunnelProvider.TunnelStartAttemptStep

    private static let canFireKey = "VPNTunnelStartPixelHandler.canFire"
    private static let lastFireDateKey = "VPNTunnelStartPixelHandler.lastFireDate"

    private let userDefaults: UserDefaults
    private let systemBootDate: Date
    private let eventHandler: EventMapping<Event>

    init(eventHandler: EventMapping<Event>,
         systemBootDate: Date = ProcessInfo.systemBootDate(),
         userDefaults: UserDefaults) {

        self.userDefaults = userDefaults
        self.systemBootDate = systemBootDate
        self.eventHandler = eventHandler
    }

    func handle(_ step: Step, onDemand: Bool) {
        if shouldResumeFiring(onDemand: onDemand) {
            canFire = true
        }

        if canFire {
            let event = Event.tunnelStartAttempt(step)
            eventHandler.fire(event)
        }

        switch step {
        case .failure where onDemand == true:
            // After firing an on-demand start failure, we always silence pixels
            canFire = false
        case .success:
            // A success always restores firing
            canFire = true
        default:
            break
        }
    }

    private func shouldResumeFiring(onDemand: Bool) -> Bool {
        guard onDemand else {
            return true
        }

        return lastFireDate < systemBootDate
    }

    // MARK: - User Defaults stored values

    var canFire: Bool {
        get {
            userDefaults.value(forKey: Self.canFireKey) as? Bool ?? true
        }

        set {
            userDefaults.setValue(newValue, forKey: Self.canFireKey)
        }
    }

    private var lastFireDate: Date {
        let interval = userDefaults.value(forKey: Self.lastFireDateKey) as? TimeInterval ?? 0
        return Date(timeIntervalSinceReferenceDate: interval)
    }

    private func updateLastFireDate() {
        let interval = Date().timeIntervalSinceReferenceDate
        userDefaults.setValue(interval, forKey: Self.lastFireDateKey)
    }
}
