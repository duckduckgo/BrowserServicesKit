//
//  ControllerErrorMesssageObserverThroughDistributedNotifications.swift
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

#if os(macOS)

import Combine
import Foundation
import NetworkExtension
import NotificationCenter
import Common

/// Observes the tunnel status through Distributed Notifications.
///
public class ControllerErrorMesssageObserverThroughDistributedNotifications: ControllerErrorMesssageObserver {
    public typealias Value = ConnectionStatus

    public lazy var publisher: AnyPublisher<String?, Never> = subject.eraseToAnyPublisher()
    public var recentValue: String? {
        subject.value
    }

    private let subject = CurrentValueSubject<String?, Never>(nil)

    // MARK: - Notifications

    private let distributedNotificationCenter: DistributedNotificationCenter
    private var cancellable: AnyCancellable?

    // MARK: - Logging

    private let log: OSLog

    // MARK: - Initialization

    public init(distributedNotificationCenter: DistributedNotificationCenter = .default(),
                log: OSLog = .networkProtectionStatusReporterLog) {

        self.distributedNotificationCenter = distributedNotificationCenter
        self.log = log

        start()
    }

    private func start() {
        cancellable = distributedNotificationCenter.publisher(for: .controllerErrorChanged).sink { [weak self] notification in
            self?.handleControllerErrorStatusChanged(notification)
        }
    }

    // MARK: - Updating controller errors

    private func handleControllerErrorStatusChanged(_ notification: Notification) {
        let errorMessage = notification.object as? String
        logErrorChanged(isShowingError: errorMessage != nil)

        subject.send(errorMessage)
    }

    // MARK: - Logging

    private func logErrorChanged(isShowingError: Bool) {
        if isShowingError {
            os_log("%{public}@: error message set", log: log, type: .debug, String(describing: self))
        } else {
            os_log("%{public}@: error message cleared", log: log, type: .debug, String(describing: self))
        }
    }
}

#endif
