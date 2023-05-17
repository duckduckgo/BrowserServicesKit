//
//  DDGSyncing.swift
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
import DDGSyncCrypto
import Combine

public enum SyncAuthState: String, Sendable, Codable {
    /// Sync is not enabled.
    case inactive
    /// Sync is in progress of registering new account.
    case setupNewAccount
    /// Sync is in progress of adding a new device to an existing account.
    case addNewDevice
    /// User is logged in to sync.
    case active
}

public protocol DataProviderProviding: AnyObject {
    func dataProviders() -> [DataProviding]
}

public protocol DDGSyncing {

    var dataProvidersProvider: DataProviderProviding? { get }

    /**
     Describes current state of sync account.
     */
    var authState: SyncAuthState { get }

    /**
     Emits changes to current state of sync account.
     */
    var authStatePublisher: AnyPublisher<SyncAuthState, Never> { get }

    /**
     The currently logged in sync account. Returns nil if client is not authenticated
     */
    var account: SyncAccount? { get }

    /**
     Used to trigger Sync by the client app.

     Sync is not started directly, but instead its schedule is handled internally based on input events.
     Clients should use `scheduler` and `Scheduling` API to notify Sync about app events, such as making
     changes to syncable data or lifecycle-related events.
     */
    var scheduler: Scheduling { get }

    /**
     Emits boolean values representing current sync operation status.
     */
    var isInProgressPublisher: AnyPublisher<Bool, Never> { get }

    /**
     Creates an account.

     Account creation has the following flow:
     * Create a device id, user id and password (UUIDs - future versions will support passing these in)
     * Generate secure keys
     * Call /signup endpoint
     * Store Primary Key, Secret Key, User Id and JWT token
     
     Notes:
     * The primary key in combination with the user id, is the recovery code.  This can be used to (re)connect devices.
     * The JWT token contains the authorisation required to call an endpoint.  If a device is removed from sync the token will be invalidated on the server and subsequent calls will fail.

     */
    func createAccount(deviceName: String, deviceType: String) async throws

    /**
     Logs in to an existing account using a recovery key.
     */
    func login(_ recoveryKey: SyncCode.RecoveryKey, deviceName: String, deviceType: String) async throws

    /**
    Returns a device id and temporary secret key ready for display and allows callers attempt to fetch the transmitted recovery key.
     */
    func remoteConnect() throws -> RemoteConnecting

    /**
     Sends this device's recovery key to the server encrypted using supplied key
     */
    func transmitRecoveryKey(_ connectCode: SyncCode.ConnectCode) async throws

    /**
     Disconnect this client from the sync service. Removes all local info, but leaves in places bookmarks, etc.
     */
    func disconnect() async throws

    /**
     Disconnect the specified device from the sync service.

     - Parameter deviceId: ID of the device to be disconnected.
    */
    func disconnect(deviceId: String) async throws

    /**
     Fetch the devices associated with thtis account.
     */
    func fetchDevices() async throws -> [RegisteredDevice]

    /**
    Updated the device name.
     */
    func updateDeviceName(_ name: String) async throws -> [RegisteredDevice]

    /**
     Deletes this account, but does not affect locally stored data.
     */
    func deleteAccount() async throws

}


public protocol Crypting {

    func encryptAndBase64Encode(_ value: String) throws -> String

    func base64DecodeAndDecrypt(_ value: String) throws -> String

}


public protocol RemoteConnecting {

    var code: String { get }

    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey?

    func stopPolling()

}

/**
 * Describes Sync scheduler.
 *
 * Client apps can call scheduler API directly to notify about events
 * that should trigger sync.
 */
public protocol Scheduling {
    /// This should be called whenever any syncable object changes.
    func notifyDataChanged()
    /// This should be called on application launch and when the app becomes active.
    func notifyAppLifecycleEvent()
    /// This should be called from externally scheduled background jobs that trigger sync periodically.
    func requestSyncImmediately()
}

/**
 * Defines sync feature, i.e. type of synced data.
 */
public struct Feature: Hashable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

/**
 * Describes a data model that is supported by Sync.
 *
 * Any data model that is passed to Sync is supposed to be encrypted as needed.
 */
public struct Syncable {
    public var payload: [String: Any]

    public init(jsonObject: [String: Any]) {
        payload = jsonObject
    }
}

/**
 * Describes data source for objects to be synced with the server.
 */
public protocol DataProviding {
    /**
     * Feature that is supported by this provider.
     *
     * This is passed to `GET /{types_csv}`.
     */
    var feature: Feature { get }

    /**
     * Time of last successful sync of a given feature.
     *
     * Note that it's a String as this is the server timestamp and should not be treated as date
     * and as such used in comparing timestamps. It's merely an identifier of the last sync operation.
     */
    var lastSyncTimestamp: String? { get }

    /**
     * Prepare data models for first sync.
     *
     * This function is called before the initial sync is performed.
     */
    func prepareForFirstSync() async throws

    /**
     * Return objects that have changed since last sync, or all objects in case of the initial sync.
     */
    func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable]

    /**
     * Apply initial sync operation response.
     *
     * - Parameter received: Objects that were received from the server.
     * - Parameter clientTimestamp: Local timestamp of the sync network request.
     * - Parameter serverTimestamp: Server timestamp describing server data validity.
     * - Parameter crypter: Crypter object to decrypt received data.
     */
    func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws

    /**
     * Apply sync operation result.
     *
     * - Parameter sent: Objects that were sent to the server.
     * - Parameter received: Objects that were received from the server.
     * - Parameter clientTimestamp: Local timestamp of the sync network request.
     * - Parameter serverTimestamp: Server timestamp describing server data validity.
     * - Parameter crypter: Crypter object to decrypt sent and received data.
     */
    func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws

    /**
     * Called when sync operation fails.
     *
     * - Parameter error: Sync operation error.
     */
    func handleSyncError(_ error: Error)
}
