//
//  SyncEngine.swift
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

/**
 * Describes a data model that is supported by Sync.
 */
public protocol Syncable: Codable, Equatable {
    var id: String { get }
    var lastModified: Date? { get set }
    var deleted: String? { get set }
}

/**
 * Defines sync feature, i.e. type of synced data.
 */
public struct SyncFeature: Hashable {
    var name: String
}

/**
 * Describes Sync scheduler.
 *
 * Client apps can call scheduler API directly to notify about events
 * that should trigger sync.
 */
public protocol SyncScheduling {
    /// This should be called whenever any syncable object changes.
    func notifyDataChanged()
    /// This should be called on application launch and when the app becomes active.
    func notifyAppLifecycleEvent()
    /// This should be called from externally scheduled background jobs that trigger sync periodically.
    func requestSyncImmediately()
}

protocol SyncSchedulingInternal: SyncScheduling {
    /// This is "internal" to BSK (for the Sync Engine to hook up to scheduler). May be extracted into a separate internal protocol.
    /// Publishes events to notify Sync Engine about
    var startSyncPublisher: AnyPublisher<Void, Never> { get }
}

/**
 * Describes data source for objects to be synced with the server.
 */
public protocol SyncDataProviding {
    /**
     * Features that are currently supported by the client app.
     *
     * This is passed to `GET /{types_csv}`.
     */
    var supportedFeatures: [SyncFeature] { get }

    /// Can possibly be internal. See `SyncMetadataProviding`.
    var metadataProvider: SyncMetadataProviding { get }

    /**
     * Client apps should implement this function and return data to be synced for `feature` based on `timestamp`.
     *
     * If `timestamp` is nil, include all objects.
     */
    func changes(for feature: SyncFeature, since timestamp: String?) async throws -> [any Syncable]
}

/**
 * Describes data source for sync metadata.
 */
public protocol SyncMetadataProviding {
    func lastSyncTimestamp(for feature: SyncFeature) -> String?
    func setLastSyncTimestamp(_ timestamp: String, for model: SyncFeature)
}

/**
 * Public interface for sync engine.
 */
public protocol SyncEngineProtocol {
    /// Used for scheduling sync
    var scheduler: SyncScheduling { get }
    /// Used for passing data to sync
    var dataProvider: SyncDataProviding { get }
    /// Used for reading sync data
    var resultsPublisher: AnyPublisher<SyncResultProviding, Never> { get }
}

/**
 * Data returned by sync engine's resultsPublisher.
 *
 * Can be queried by client apps to retrieve changes.
 */
public protocol SyncResultProviding {
    func changes(for feature: SyncFeature) -> [any Syncable]

    /// If we make SyncMetadataProviding internal, then this can be internal too.
    func lastSyncTimestamp(for feature: SyncFeature) -> String?
}

/**
 * Internal interface for sync engine.
 */
protocol SyncWorkerProtocol {
    var dataProvider: SyncDataProviding { get }

    func sync() async throws -> SyncResultProviding
}

// MARK: - Example Implementation

class SyncScheduler: SyncSchedulingInternal {
    func notifyDataChanged() {
        syncTriggerSubject.send()
    }

    func notifyAppLifecycleEvent() {
        appLifecycleEventSubject.send()
    }

    func requestSyncImmediately() {
        syncTriggerSubject.send()
    }

    let startSyncPublisher: AnyPublisher<Void, Never>

    init() {
        let throttledAppLifecycleEvents = appLifecycleEventSubject
            .throttle(for: .seconds(Const.appLifecycleEventsDebounceInterval), scheduler: DispatchQueue.main, latest: true)

        let throttledSyncTriggerEvents = syncTriggerSubject
            .throttle(for: .seconds(Const.immediateSyncDebounceInterval), scheduler: DispatchQueue.main, latest: true)

        startSyncPublisher = startSyncSubject.eraseToAnyPublisher()

        Publishers.Merge(throttledAppLifecycleEvents, throttledSyncTriggerEvents)
            .sink(receiveValue: { [weak self] _ in
                self?.startSyncSubject.send()
            })
            .store(in: &cancellables)
    }

    private let appLifecycleEventSubject: PassthroughSubject<Void, Never> = .init()
    private let syncTriggerSubject: PassthroughSubject<Void, Never> = .init()
    private let startSyncSubject: PassthroughSubject<Void, Never> = .init()
    private var cancellables: Set<AnyCancellable> = []

    enum Const {
        static let immediateSyncDebounceInterval = 1
        static let appLifecycleEventsDebounceInterval = 600
    }
}

struct SyncDataProvider: SyncDataProviding {
    var supportedFeatures: [SyncFeature] {
        [.init(name: "bookmarks")]
    }

    let metadataProvider: SyncMetadataProviding

    init(metadataProvider: SyncMetadataProviding) {
        self.metadataProvider = metadataProvider
    }

    func changes(for feature: SyncFeature, since timestamp: String?) async -> [any Syncable] {
        []
    }
}

struct SyncMetadataProvider: SyncMetadataProviding {
    func lastSyncTimestamp(for feature: SyncFeature) -> String? {
        nil
    }

    func setLastSyncTimestamp(_ timestamp: String, for model: SyncFeature) {
    }
}

struct SyncResultProvider: SyncResultProviding {
    func lastSyncTimestamp(for feature: SyncFeature) -> String? {
        timestamps[feature]
    }

    func changes(for feature: SyncFeature) -> [any Syncable] {
        var changedObjects = received[feature] ?? []
        let receivedObjectsIDs = Set(changedObjects.map(\.id))

        let sentObjects: [any Syncable] = (sent[feature] ?? []).filter { !receivedObjectsIDs.contains($0.id) }
        changedObjects.append(contentsOf: sentObjects)

        return changedObjects
    }

    var sent: [SyncFeature: [any Syncable]] = [:]
    var received: [SyncFeature: [any Syncable]] = [:]
    var timestamps: [SyncFeature: String] = [:]
}

class SyncEngine: SyncEngineProtocol {

    init(
        dataProvider: SyncDataProviding,
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints,
        scheduler: SyncSchedulingInternal = SyncScheduler()
    ) {
        self.scheduler = scheduler
        self.dataProvider = dataProvider
        self.worker = SyncWorker(dataProvider: dataProvider, api: api, endpoints: endpoints)

        resultsPublisher = resultsSubject.eraseToAnyPublisher()

        scheduler.startSyncPublisher
            .sink { [weak self] _ in
                self?.performSync()
            }
            .store(in: &cancellables)
    }

    let scheduler: SyncScheduling
    let dataProvider: SyncDataProviding
    let resultsPublisher: AnyPublisher<SyncResultProviding, Never>

    private let worker: SyncWorkerProtocol
    private let resultsSubject = PassthroughSubject<SyncResultProviding, Never>()

    private func performSync() {
        Task {
            let results = try await worker.sync()
            resultsSubject.send(results)
        }
    }

    private var cancellables: Set<AnyCancellable> = []
}

actor SyncWorker: SyncWorkerProtocol {

    let dataProvider: SyncDataProviding
    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating

    init(
        dataProvider: SyncDataProviding,
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        self.dataProvider = dataProvider
        self.endpoints = endpoints
        self.api = api
    }

    func sync() async throws -> SyncResultProviding {
        var result = SyncResultProvider()

        result.sent = try await withThrowingTaskGroup(of: [SyncFeature: [any Syncable]].self) { group in
            var sent = [SyncFeature: [any Syncable]]()

            for feature in dataProvider.supportedFeatures {
                let localChanges = try await dataProvider.changes(for: feature, since: dataProvider.metadataProvider.lastSyncTimestamp(for: feature))
                sent[feature] = localChanges
            }
            return sent
        }

        // TODO
        // * enumerate dataProvider.supportedFeatures:
        //   * collect last sync timestamp and changes per feature
        //   * if there are changes, use PATCH, otherwise use GET
        // * send request
        // * read response
        // * update result

        return result
    }
}
