//
//  ProductionDependencies.swift
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
import Common

struct ProductionDependencies: SyncDependencies {

    let fileStorageUrl: URL
    let endpoints: Endpoints
    let account: AccountManaging
    let api: RemoteAPIRequestCreating
    let secureStore: SecureStoring
    let crypter: CryptingInternal
    let scheduler: SchedulingInternal
    let errorEvents: EventMapping<SyncError>

    var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog

    init(baseUrl: URL, errorEvents: EventMapping<SyncError>, log: @escaping @autoclosure () -> OSLog = .disabled) {
        
        self.init(fileStorageUrl: FileManager.default.applicationSupportDirectoryForComponent(named: "Sync"),
                  baseUrl: baseUrl,
                  secureStore: SecureStorage(),
                  errorEvents: errorEvents,
                  log: log())
    }
    
    init(
        fileStorageUrl: URL,
        baseUrl: URL,
        secureStore: SecureStoring,
        errorEvents: EventMapping<SyncError>,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.fileStorageUrl = fileStorageUrl
        self.endpoints = Endpoints(baseUrl: baseUrl)
        self.secureStore = secureStore
        self.errorEvents = errorEvents
        self.getLog = log

        api = RemoteAPIRequestCreator(log: log())

        crypter = Crypter(secureStore: secureStore)
        account = AccountManager(endpoints: endpoints, api: api, crypter: crypter)
        scheduler = SyncScheduler()
    }

    func createRemoteConnector(_ info: ConnectInfo) throws -> RemoteConnecting {
        return try RemoteConnector(crypter: crypter, api: api, endpoints: endpoints, connectInfo: info)
    }

    func createRecoveryKeyTransmitter() throws -> RecoveryKeyTransmitting {
        return RecoveryKeyTransmitter(endpoints: endpoints, api: api, storage: secureStore, crypter: crypter)
    }

}
