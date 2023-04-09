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
public struct SyncFeature: Equatable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
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
    associatedtype SyncableModel: Syncable
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
    var lastSyncTimestamp: String? { get }

    /**
     * Client apps should implement this function and return data to be synced for a given feature based on `timestamp`.
     *
     * If `timestamp` is nil, include all objects.
     */
    func changes(since timestamp: String?) async throws -> [SyncableModel]

    func encode(_ syncables: [any Syncable], to encoder: Encoder) throws
    static func decode(from decoder: Decoder) throws -> ([SyncableModel], String)
}

/**
 * Public interface for sync results publisher.
 */
public protocol SyncResultsPublishing {
    /// Used for receiving sync data
    var results: AnyPublisher<[SyncResultProviding], Never> { get }
}

/**
 * Internal interface for sync engine.
 */
protocol SyncEngineProtocol: SyncResultsPublishing {
    /// Used for passing data to sync
    var dataProviders: [any SyncDataProviding] { get }
    /// Called to start sync
    func startSync()
}

/**
 * Data returned by sync engine's results publisher.
 *
 * Can be queried by client apps to retrieve changes.
 */
public protocol SyncResultProviding {
    var feature: SyncFeature { get }
    var sent: [any Syncable] { get }
    var received: [any Syncable] { get }
    var lastSyncTimestamp: String? { get }
}

/**
 * Internal interface for sync engine.
 */
protocol SyncWorkerProtocol {
    var dataProviders: [any SyncDataProviding] { get }

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

/**
 * Example Syncable model implementation
 */
public struct SyncableBookmark: Syncable {
    public var id: String
    public var lastModified: Date?
    public var deleted: String?
}

/**
 * Example SyncDataProvider implementation
 */
struct SyncDataProvider: SyncDataProviding {
    typealias SyncableModel = SyncableBookmark

    let feature: SyncFeature = .init(name: "bookmarks")

    var lastSyncTimestamp: String? {
        nil
    }

    func changes(since timestamp: String?) async throws -> [SyncableModel] {
        []
    }

    func encode(_ syncables: [any Syncable], to encoder: Encoder) throws {
        if let bookmarks = syncables as? [SyncableBookmark] {
            var container = encoder.singleValueContainer()
            try container.encode(bookmarks)
        }
    }

    static func decode(from decoder: Decoder) throws -> ([SyncableBookmark], String) {

        struct Temp: Decodable {
            let lastModified: String
            let entries: [SyncableBookmark]

            enum CodingKeys: String, CodingKey {
                case lastModified, entries
            }
        }

        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let temp = try container.decode(Temp.self, forKey: AnyCodingKey(stringValue: "bookmarks"))
        return (temp.entries, temp.lastModified)
    }
}

struct SyncResultProvider: SyncResultProviding {
    let feature: SyncFeature

    var sent: [any Syncable] = []
    var received: [any Syncable] = []
    var lastSyncTimestamp: String?
}

class SyncEngine: SyncEngineProtocol {

    let dataProviders: [any SyncDataProviding]
    let results: AnyPublisher<[SyncResultProviding], Never>

    init(
        dataProviders: [any SyncDataProviding],
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        self.dataProviders = dataProviders
        self.worker = SyncWorker(dataProviders: dataProviders, api: api, endpoints: endpoints)

        results = resultsSubject.eraseToAnyPublisher()
    }

    func startSync() {
        Task {
            let results = try await worker.sync()
            resultsSubject.send(results)
        }
    }

    private let worker: SyncWorkerProtocol
    private let resultsSubject = PassthroughSubject<[SyncResultProviding], Never>()
}

actor SyncWorker: SyncWorkerProtocol {

    let dataProviders: [any SyncDataProviding]
    let endpoints: Endpoints
    let api: RemoteAPIRequestCreating

    init(
        dataProviders: [any SyncDataProviding],
        api: RemoteAPIRequestCreating,
        endpoints: Endpoints
    ) {
        self.dataProviders = dataProviders
        self.endpoints = endpoints
        self.api = api
    }

    func sync() async throws -> [SyncResultProviding] {

        // Collect last sync timestamp and changes per feature
        let resultsAndPayloads = try await withThrowingTaskGroup(of: ([SyncResultProvider], [FeaturePayload]).self) { group in
            var results = [SyncResultProvider]()
            var payloads = [FeaturePayload]()

            for dataProvider in self.dataProviders {
                let localChanges = try await dataProvider.changes(since: dataProvider.lastSyncTimestamp)
                let resultProvider = SyncResultProvider(feature: dataProvider.feature, sent: localChanges)
                results.append(resultProvider)

                let payload = FeaturePayload(
                    featureName: dataProvider.feature.name,
                    updates: localChanges,
                    modifiedSince: dataProvider.lastSyncTimestamp
                ) { syncables, encoder in
                    try dataProvider.encode(syncables, to: encoder)
                }

                payloads.append(payload)
            }
            return (results, payloads)
        }

        let (results, payloads) = resultsAndPayloads

        let request: HTTPRequesting = try {
            let hasLocalChanges = results.contains(where: { !$0.sent.isEmpty })
            guard hasLocalChanges else {
                return api.createRequest(url: endpoints.syncGet, method: .GET, headers: [:], parameters: [:], body: nil, contentType: nil)
            }

            let payload = SyncPatchPayload(featurePayloads: payloads)
            let body = try JSONEncoder().encode(payload)

            return api.createRequest(url: endpoints.syncPatch, method: .PATCH, headers: [:], parameters: [:], body: body, contentType: "application/json")
        }()

        let result = try await request.execute()

        guard let data = result.data else {
            throw SyncError.noResponseBody
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

struct SyncEncodingError: Error {}

struct SyncPatchPayload: Encodable {
    let featurePayloads: [FeaturePayload]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for featurePayload in featurePayloads {
            try container.encode(featurePayload, forKey: AnyCodingKey(stringValue: featurePayload.featureName))
        }
    }
}

struct FeaturePayload: Encodable {
    let featureName: String
    let updates: [any Syncable]
    let modifiedSince: String?
    let encodeUpdates: ([any Syncable], Encoder) throws -> Void

    enum CodingKeys: String, CodingKey {
        case updates, modifiedSince
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiedSince, forKey: .modifiedSince)
        try encodeUpdates(updates, container.superEncoder(forKey: .updates))
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

struct FeatureResponsePayload<S: SyncDataProviding>: Decodable {
    let entries: [S.SyncableModel]
    let lastModified: String

    init(from decoder: Decoder) throws {
        (entries, lastModified) = try S.decode(from: decoder)
    }
}
