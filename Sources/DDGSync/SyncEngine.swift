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
 * Defines sync feature, i.e. type of synced data.
 */
public struct SyncFeature {
    var name: String
}

/**
 * Describes a data model that is supported by Sync.
 *
 * Any data model that is passed to Sync Engine is supposed to be encrypted as needed.
 */
public protocol Syncable: Codable, Equatable {
    var id: String { get }
    var lastModified: Date? { get set }
    var deleted: String? { get set }
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
     * Feature that is supported by this provider.
     *
     * This is passed to `GET /{types_csv}`.
     */
    var feature: SyncFeature { get }

    /**
     * Time of last successful sync of a given feature.
     *
     * Note that it's a String as this is the server timestamp and should not be treated as date
     * and as such used in comparing timestamps. It's merely an identifier of last sync.
     */
    var lastSyncTimestamp: String? { get set }

    /**
     * Client apps should implement this function and return data to be synced for `feature` based on `timestamp`.
     *
     * If `timestamp` is nil, include all objects.
     */
    func changes(since timestamp: String?) async throws -> [any Syncable]
}

/**
 * Public interface for sync engine.
 */
public protocol SyncEngineProtocol {
    /// Used for passing data to sync
    var dataProviders: [SyncDataProviding] { get }
    /// Used for reading sync data
    var resultsPublisher: AnyPublisher<[SyncResultProviding], Never> { get }
}

/**
 * Internal interface for sync engine.
 */
protocol SyncEngineProtocolInternal: SyncEngineProtocol {
    /// Called to start sync
    func startSync()
}

/**
 * Data returned by sync engine's resultsPublisher.
 *
 * Can be queried by client apps to retrieve changes.
 */
public protocol SyncResultProviding {
    var feature: SyncFeature { get }
    var changes: [any Syncable] { get }
    var lastSyncTimestamp: String? { get }
}

/**
 * Internal interface for sync engine.
 */
protocol SyncWorkerProtocol {
    var dataProviders: [SyncDataProviding] { get }

    func sync() async throws -> [SyncResultProviding]
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
    let feature: SyncFeature = .init(name: "bookmarks")

    var lastSyncTimestamp: String? {
        get {
            // TODO fetch from database
            return nil
        }
        set {
            // TODO store in database
        }
    }

    func changes(since timestamp: String?) async throws -> [any Syncable] {
        []
    }
}

struct SyncResultProvider: SyncResultProviding {
    let feature: SyncFeature

    var lastSyncTimestamp: String?

    var changes: [any Syncable] {
        let receivedObjectsIDs = Set(received.map(\.id))
        var changedObjects = received

        let sentObjects: [any Syncable] = sent.filter { !receivedObjectsIDs.contains($0.id) }
        changedObjects.append(contentsOf: sentObjects)

        return changedObjects
    }

    var sent: [any Syncable] = []
    var received: [any Syncable] = []
}

class SyncEngine: SyncEngineProtocolInternal {

    let dataProviders: [SyncDataProviding]
    let resultsPublisher: AnyPublisher<[SyncResultProviding], Never>

    init(
        dataProviders: [SyncDataProviding],
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        self.dataProviders = dataProviders
        self.worker = SyncWorker(dataProviders: dataProviders, api: api, endpoints: endpoints)

        resultsPublisher = resultsSubject.eraseToAnyPublisher()
    }

    func startSync() {
        Task {
            let results = try await worker.sync()
            resultsSubject.send(results)
        }
    }

    private let worker: SyncWorkerProtocol
    private let resultsSubject = PassthroughSubject<[SyncResultProviding], Never>()

    private var cancellables: Set<AnyCancellable> = []
}

actor SyncWorker: SyncWorkerProtocol {

    let dataProviders: [SyncDataProviding]
    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating

    init(
        dataProviders: [SyncDataProviding],
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        self.dataProviders = dataProviders
        self.endpoints = endpoints
        self.api = api
    }

    func sync() async throws -> [SyncResultProviding] {

        // Collect last sync timestamp and changes per feature
        let results: [SyncResultProvider] = try await withThrowingTaskGroup(of: [SyncResultProvider].self) { group in
            var results = [SyncResultProvider]()

            for dataProvider in dataProviders {
                let localChanges = try await dataProvider.changes(since: dataProvider.lastSyncTimestamp)
                let resultProvider = SyncResultProvider(feature: dataProvider.feature, sent: localChanges)
                results.append(resultProvider)
            }
            return results
        }

        // TODO
        // * enumerate dataProvider.supportedFeatures:
        //   * if there are changes, use PATCH, otherwise use GET
        // * send request
        // * read response
        // * update result

        return results
    }
}
