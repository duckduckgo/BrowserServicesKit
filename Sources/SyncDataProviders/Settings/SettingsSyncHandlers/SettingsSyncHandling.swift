//
//  SettingsSyncHandling.swift
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

import Combine
import Foundation
import Persistence

/**
 * Error that may occur while updating timestamp when a setting changes.
 *
 * This error should be published via `SettingsSyncHandling.errorPublisher`
 * whenever settings metadata database fails to save changes after updating
 * timestamp for a given setting.
 *
 * `underlyingError` should contain the actual Core Data error.
 */
public struct SettingsSyncMetadataSaveError: Error {
    public let underlyingError: Error

    public init(underlyingError: Error) {
        self.underlyingError = underlyingError
    }
}

/**
 * Protocol defining communication between Settings Sync Data Provider and a syncable setting.
 *
 * This protocol should be implemented by classes or structs providing integration with Sync
 * for given settings (or, more broadly, key-value pairs).
 *
 * Its responsibilities are:
 *   * provide implementation for getting and updating the setting's value,
 *   * fine-tune Sync behavior for the setting,
 *   * track changes to setting's value and update metadata database timestamp accordingly.
 */
public protocol SettingsSyncHandling {
    /**
     * Returns setting identifier that this handler supports.
     *
     * `setting.key` is used verbatim as key in the JSON Sync payload.
     */
    var setting: SettingsProvider.Setting { get }

    /// Retrieves setting value.
    func getValue() throws -> String?

    /// Updates setting value with `value` received from Sync.
    func setValue(_ value: String?) throws

    /**
     * Controls setting behavior during initial sync.
     *
     * Upon initial sync, the setting for the given key may be deleted on the server.
     * The default Sync behavior is to delete (clear) equivalent local setting.
     *
     * Return `false` here if local setting should not be deleted and should
     * override server value.
     *
     * Example: when Sync account has Email Protection disabled on the server,
     * adding a new device with Email Protection enabled to Sync should propagate
     * that Email Protection credentials to other devices, hence Email Protection
     * Sync Handler returns `false` here.
     */
    var shouldApplyRemoteDeleteOnInitialSync: Bool { get }

    /**
     * Publishes errors thrown internally by the handler.
     *
     * For example, when metadata database fails to save after updating setting's value.
     */
    var errorPublisher: AnyPublisher<Error, Never> { get }
}
