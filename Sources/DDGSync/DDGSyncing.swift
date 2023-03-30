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
    Returns a device id and temporary secret key ready for display then polls the end point for a recovery key.
     */
    func remoteConnect() throws -> RemoteConnecting

    /**
     Sends this device's recovery key to the server encrypted using supplied key
     */
    func transmitRecoveryKey(_ connectCode: SyncCode.ConnectCode) async throws

    /**
    Creates an atomic sender.  Add items to the sender and then call send to send them all in a single PATCH.  Will automatically re-try if there is a network failure.
     */
    func sender() throws -> UpdatesSending

    /**
    Call this to call the server and get latest updated.
     */
    func fetchLatest() async throws

    /**
     Call this to fetch everything again.
    */
    func fetchEverything() async throws

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

public protocol UpdatesSending {

    func persistingBookmark(_ bookmark: SavedSiteItem) throws -> UpdatesSending
    func persistingBookmarkFolder(_ folder: SavedSiteFolder) throws -> UpdatesSending
    func deletingBookmark(_ bookmark: SavedSiteItem) throws -> UpdatesSending
    func deletingBookmarkFolder(_ folder: SavedSiteFolder) throws -> UpdatesSending

    func send() async throws

}

public enum SyncEvent {

    case bookmarkUpdated(SavedSiteItem)
    case bookmarkFolderUpdated(SavedSiteFolder)
    case bookmarkDeleted(id: String)

}

public struct SavedSiteItem: Codable {

    public let id: String

    public let title: String
    public let url: String

    public let isFavorite: Bool
    public let nextFavorite: String?

    public let nextItem: String?
    public let parent: String?

    public init(id: String,
                title: String,
                url: String,
                isFavorite: Bool,
                nextFavorite: String?,
                nextItem: String?,
                parent: String?) {

        self.id = id
        self.title = title
        self.url = url
        self.isFavorite = isFavorite
        self.nextFavorite = nextFavorite
        self.nextItem = nextItem
        self.parent = parent

    }

}

public struct SavedSiteFolder: Codable {

    public let id: String

    public let title: String

    public let nextItem: String?
    public let parent: String?

    public init(id: String, title: String, nextItem: String?, parent: String?) {
        self.id = id
        self.title = title
        self.nextItem = nextItem
        self.parent = parent
    }

}

public protocol RemoteConnecting {

    var code: String { get }

    func fetchRecoveryKey() async throws -> SyncCode.RecoveryKey?
    
}
