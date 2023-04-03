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

public protocol DDGSyncing {

    /**
     This client is authenticated if there is an account and a non-null token. If the token is invalidated remotely subsequent requests will set the token to nil and throw an exception.
     */
    var isAuthenticated: Bool { get }

    /**
     This client is authenticated if there is an account and a non-null token. If the token is invalidated remotely subsequent requests will set the token to nil and throw an exception.
     */
    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> { get }

    /**
     The currently logged in sync account. Returns nil if client is not authenticated
     */
    var account: SyncAccount? { get }

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

     @param deviceId ID of the device to be disconnected.
    */
    func disconnect(deviceId: String) async throws
}

public protocol RemoteConnecting {

    var code: String { get }

    func pollForRecoveryKey() async throws -> SyncCode.RecoveryKey?

    func stopPolling()

}
