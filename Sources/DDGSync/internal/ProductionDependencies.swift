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
    let scheduler: SyncSchedulingInternal
    let engine: SyncEngineProtocolInternal

    private let persistence: LocalDataPersisting

    init(baseUrl: URL, persistence: LocalDataPersisting, dataProviders: [SyncDataProviding]) {
        
        self.init(fileStorageUrl: FileManager.default.applicationSupportDirectoryForComponent(named: "Sync"),
                  baseUrl: baseUrl,
                  persistence: persistence,
                  dataProviders: dataProviders,
                  secureStore: SecureStorage())
    }
    
    init(fileStorageUrl: URL, baseUrl: URL, persistence: LocalDataPersisting, dataProviders: [SyncDataProviding], secureStore: SecureStoring) {
        self.fileStorageUrl = fileStorageUrl
        self.endpoints = Endpoints(baseUrl: baseUrl)
        self.persistence = persistence
        self.secureStore = secureStore

        api = RemoteAPIRequestCreator()

        crypter = Crypter(secureStore: secureStore)
        account = AccountManager(endpoints: endpoints, api: api, crypter: crypter)
        scheduler = SyncScheduler()
        engine = SyncEngine(dataProviders: dataProviders, api: api, endpoints: endpoints)
    }

    func createRemoteConnector(_ info: ConnectInfo) throws -> RemoteConnecting {
        return try RemoteConnector(crypter: crypter, api: api, endpoints: endpoints, connectInfo: info)
    }

    func createRecoveryKeyTransmitter() throws -> RecoveryKeyTransmitting {
        return RecoveryKeyTransmitter(endpoints: endpoints, api: api, storage: secureStore, crypter: crypter)
    }

}
