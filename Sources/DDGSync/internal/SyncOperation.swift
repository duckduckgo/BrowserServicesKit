//
//  SyncOperation.swift
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

import Foundation
import Combine
import Common
import os

class SyncOperation: Operation {

    private(set) var error: Error?

    let dataProviders: [Feature: DataProviding]
    let storage: SecureStoring
    let crypter: Crypting
    let requestMaker: SyncRequestMaking
    let firstFetchCompletion: (() -> Void)?

    convenience init(
        dataProviders: [DataProviding],
        storage: SecureStoring,
        crypter: Crypting,
        requestMaker: SyncRequestMaking,
        log: @escaping @autoclosure () -> OSLog = .disabled,
        firstFetchCompletion: (() -> Void)? = nil
    ) {
        let dataProvidersMap: [Feature: DataProviding] = dataProviders.reduce(into: .init(), { partialResult, provider in
            partialResult[provider.feature] = provider
        })

        self.init(
            dataProviders: dataProvidersMap,
            storage: storage,
            crypter: crypter,
            requestMaker: requestMaker,
            log: log(),
            firstFetchCompletion: firstFetchCompletion
        )
    }

    init(
        dataProviders: [Feature: DataProviding],
        storage: SecureStoring,
        crypter: Crypting,
        requestMaker: SyncRequestMaking,
        log: @escaping @autoclosure () -> OSLog = .disabled,
        firstFetchCompletion: (() -> Void)?
    ) {
        self.dataProviders = dataProviders
        self.storage = storage
        self.crypter = crypter
        self.requestMaker = requestMaker
        self.getLog = log
        self.firstFetchCompletion = firstFetchCompletion
    }

    override func start() {
        isExecuting = true
        isFinished = false

        Task {
            defer {
                isExecuting = false
                isFinished = true
            }

            do {
                let state = try storage.account()?.state
                if state == .addingNewDevice {
                    try await sync(fetchOnly: true)
                    firstFetchCompletion?()
                }
                try await sync(fetchOnly: false)
            } catch {
                self.error = error
            }
        }
    }

    func sync(fetchOnly: Bool) async throws {
        os_log(.debug, log: log, "Sync Operation Started. Fetch-only: %{public}s", String(fetchOnly))
        defer {
            os_log(.debug, log: log, "Sync Operation Finished. Fetch-only: %{public}s", String(fetchOnly))
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (feature, dataProvider) in dataProviders {
                group.addTask { [weak self] in
                    guard let self else {
                        return
                    }
                    os_log(.debug, log: self.log, "Syncing %{public}s", feature.name)

                    do {
                        let syncRequest = try await self.makeSyncRequest(for: dataProvider, fetchOnly: fetchOnly)
                        let clientTimestamp = Date()
                        let httpRequest = try self.makeHTTPRequest(with: syncRequest, timestamp: clientTimestamp)
                        let httpResult: HTTPResult = try await httpRequest.execute()

                        switch httpResult.response.statusCode {
                        case 200:
                            guard let data = httpResult.data else {
                                throw SyncError.noResponseBody
                            }
                            os_log(.debug, log: self.log, "Response for %{public}s: %{public}s",
                                   feature.name,
                                   String(data: data, encoding: .utf8) ?? "")
                            let syncResult = try self.decodeResponse(with: data, request: syncRequest)
                            try await self.handleResponse(for: dataProvider, syncResult: syncResult, fetchOnly: fetchOnly, timestamp: clientTimestamp)
                        case 204, 304:
                            try await self.handleResponse(for: dataProvider, syncResult: .noData(with: syncRequest), fetchOnly: fetchOnly, timestamp: clientTimestamp)
                        default:
                            throw SyncError.unexpectedStatusCode(httpResult.response.statusCode)
                        }
                    } catch {
                        os_log(.debug, log: self.log, "Error syncing %{public}s: %{public}s", feature.name, error.localizedDescription)
                        dataProvider.handleSyncError(error)
                        throw FeatureError(feature: feature, underlyingError: error)
                    }
                }
            }

            var errors: [FeatureError] = []

            while let result = await group.nextResult() {
                if case .failure(let error) = result, let featureError = error as? FeatureError {
                    errors.append(featureError)
                }
            }

            if !errors.isEmpty {
                throw SyncOperationError(featureErrors: errors)
            }
        }
    }

    private func makeSyncRequest(for dataProvider: DataProviding, fetchOnly: Bool) async throws -> SyncRequest {
        if fetchOnly {
            return SyncRequest(feature: dataProvider.feature, previousSyncTimestamp: dataProvider.lastSyncTimestamp, sent: [])
        }
        let localChanges: [Syncable] = try await dataProvider.fetchChangedObjects(encryptedUsing: crypter)
        return SyncRequest(feature: dataProvider.feature, previousSyncTimestamp: dataProvider.lastSyncTimestamp, sent: localChanges)
    }

    private func makeHTTPRequest(with syncRequest: SyncRequest, timestamp: Date) throws -> HTTPRequesting {
        let hasLocalChanges = !syncRequest.sent.isEmpty
        if hasLocalChanges {
            return try requestMaker.makePatchRequest(with: syncRequest, clientTimestamp: timestamp)
        }
        return try requestMaker.makeGetRequest(with: syncRequest)
    }

    private func decodeResponse(with data: Data, request: SyncRequest) throws -> SyncResult {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw SyncError.unableToDecodeResponse("Failed to decode sync response")
        }

        guard let featurePayload = jsonObject[request.feature.name] as? [String: Any],
              let lastModified = featurePayload["last_modified"] as? String,
              let entries = featurePayload["entries"] as? [[String: Any]]
        else {
            throw SyncError.unexpectedResponseBody
        }
        return SyncResult(request: request, syncTimestamp: lastModified, received: entries.map(Syncable.init(jsonObject:)))
    }

    private func handleResponse(for dataProvider: DataProviding, syncResult: SyncResult, fetchOnly: Bool, timestamp: Date) async throws {
        if fetchOnly {
            try await dataProvider.handleInitialSyncResponse(
                received: syncResult.received,
                clientTimestamp: timestamp,
                serverTimestamp: syncResult.syncTimestamp,
                crypter: crypter
            )
        } else {
            try await dataProvider.handleSyncResponse(
                sent: syncResult.request.sent,
                received: syncResult.received,
                clientTimestamp: timestamp,
                serverTimestamp: syncResult.syncTimestamp,
                crypter: crypter
            )
        }
    }

    private var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog

    // MARK: - Overrides

    override var isAsynchronous: Bool { true }

    override var isExecuting: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isExecuting
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isExecuting))
            _isExecuting = newValue
            didChangeValue(forKey: #keyPath(isExecuting))
        }
    }

    override var isFinished: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isFinished
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isFinished))
            _isFinished = newValue
            didChangeValue(forKey: #keyPath(isFinished))
        }
    }

    override var isCancelled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isCancelled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isCancelled))
            _isCancelled = newValue
            didChangeValue(forKey: #keyPath(isCancelled))
        }
    }

    private let lock = NSRecursiveLock()
    private var _isExecuting: Bool = false
    private var _isFinished: Bool = false
    private var _isCancelled: Bool = false
}
