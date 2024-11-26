//
//  PrivacyStats.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import os.log
import Persistence
import TrackerRadarKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public protocol PrivacyStatsDatabaseProviding {
    func initializeDatabase() -> CoreDataDatabase
}

public protocol PrivacyStatsCollecting {
    func recordBlockedTracker(_ name: String) async
    var topCompanies: Set<String> { get }

    var currentStatsUpdatePublisher: AnyPublisher<Void, Never> { get }
    func fetchPrivacyStats() async -> [String: Int]
    func clearPrivacyStats() async
}

public protocol TrackerDataProviding {
    var trackerData: TrackerData { get }
    var trackerDataUpdatesPublisher: AnyPublisher<Void, Never> { get }
}

actor CurrentStats {
    private(set) var timestamp: Date?
    private(set) var trackers: [String: Int] = [:]
    private(set) lazy var commitChangesPublisher: AnyPublisher<([String: Int], Date), Never> = commitChangesSubject.eraseToAnyPublisher()

    private let commitChangesSubject = PassthroughSubject<([String: Int], Date), Never>()
    private var commitTask: Task<Void, Never>?

    func set(_ trackers: [String: Int], for timestamp: Date) {
        self.timestamp = timestamp
        self.trackers = trackers
    }

    func resetStats() {
        self.trackers = [:]
    }

    func recordBlockedTracker(_ name: String) {

        let currentTimestamp = Date().startOfHour
        if let timestamp, currentTimestamp != timestamp {
            commitChangesSubject.send((trackers, timestamp))
            resetStats(andSet: currentTimestamp)
        }

        let count = trackers[name] ?? 0
        trackers[name] = count + 1

        commitTask?.cancel()
        commitTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1000000000)

                if let timestamp = self.timestamp {
                    Logger.privacyStats.debug("Storing trackers state")
                    commitChangesSubject.send((trackers, timestamp))
                }
            } catch {
                // commit task got cancelled
            }
        }
    }

    private func resetStats(andSet newTimestamp: Date) {
        timestamp = newTimestamp
        trackers = [:]
    }
}

public final class PrivacyStats: PrivacyStatsCollecting {

    public static let bundle = Bundle.module

    public let trackerDataProvider: TrackerDataProviding
    public private(set) var topCompanies: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    private let db: CoreDataDatabase
    private let context: NSManagedObjectContext

    public let currentStatsUpdatePublisher: AnyPublisher<Void, Never>

    private let currentStatsUpdateSubject = PassthroughSubject<Void, Never>()

    // current pack timestamp
    private var currentStatsObject: PrivacyStatsEntity?
    private var currentStatsActor: CurrentStats

    private var commitTimer: Timer?

    private var cached7DayStats: [String: Int] = [:]
    private var cached7DayStatsLastFetchTimestamp: Date?

    public init(databaseProvider: PrivacyStatsDatabaseProviding, trackerDataProvider: TrackerDataProviding) {
        self.db = databaseProvider.initializeDatabase()
        self.context = db.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "PrivacyStats")
        self.currentStatsActor = CurrentStats()
        currentStatsUpdatePublisher = currentStatsUpdateSubject.eraseToAnyPublisher()

        self.trackerDataProvider = trackerDataProvider
        trackerDataProvider.trackerDataUpdatesPublisher
            .sink { [weak self] in
                self?.refreshTopCompanies()
            }
            .store(in: &cancellables)

        refreshTopCompanies()
        Task {
            await loadCurrentStats()
            await currentStatsActor.commitChangesPublisher
                .sink { [weak self] stats, timestamp in
                    Task {
                        await self?.commitChanges(stats, timestamp: timestamp)
                    }
                }
                .store(in: &cancellables)
        }

#if os(iOS)
        let notificationName = UIApplication.willTerminateNotification
#elseif os(macOS)
        let notificationName = NSApplication.willTerminateNotification
#endif

        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: notificationName, object: nil)
    }

    public func recordBlockedTracker(_ name: String) async {
        await currentStatsActor.recordBlockedTracker(name)
    }

    private func commitChanges(_ trackers: [String: Int], timestamp: Date) async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if let currentStatsObject, timestamp != currentStatsObject.timestamp {
                    self.currentStatsObject = PrivacyStatsEntity.make(timestamp: timestamp, context: context)
                }

                currentStatsObject?.blockedTrackersDictionary = trackers
                guard context.hasChanges else {
                    continuation.resume()
                    return
                }

                do {
                    try context.save()
                    Logger.privacyStats.debug("Saved stats \(timestamp) \(trackers)")
                    currentStatsUpdateSubject.send()
                } catch {
                    Logger.privacyStats.error("Save error: \(error)")
                }
                continuation.resume()
            }
        }
    }

    public func fetchPrivacyStats() async -> [String: Int] {
        let isCacheValid: Bool = {
            guard let cached7DayStatsLastFetchTimestamp else {
                return false
            }
            return Date.isSameHour(Date(), cached7DayStatsLastFetchTimestamp)
        }()
        if !isCacheValid {
            await refresh7DayCache()
            Task {
                await deleteOldEntries()
            }
        }
        let currentStats = await currentStatsActor.trackers
        return cached7DayStats.merging(currentStats, uniquingKeysWith: +)
    }

    public func clearPrivacyStats() async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                PrivacyStatsUtils.deleteAllStats(in: context)
                currentStatsObject = nil
                do {
                    try context.save()
                    Logger.privacyStats.debug("Deleted outdated entries")
                } catch {
                    Logger.privacyStats.error("Save error: \(error)")
                }
                continuation.resume()
            }
        }
        await currentStatsActor.resetStats()
    }

    private func refresh7DayCache() async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                cached7DayStats = PrivacyStatsUtils.load7DayStats(in: context)
                cached7DayStatsLastFetchTimestamp = Date()
                continuation.resume()
            }
        }
    }

    private func deleteOldEntries() async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                PrivacyStatsUtils.deleteOutdatedStats(in: context)
                if context.hasChanges {
                    do {
                        try context.save()
                        Logger.privacyStats.debug("Deleted outdated entries")
                    } catch {
                        Logger.privacyStats.error("Save error: \(error)")
                    }
                }
                continuation.resume()
            }
        }
    }

    private func refreshTopCompanies() {
        struct TrackerWithPrevalence {
            let name: String
            let prevalence: Double
        }

        let trackers: [TrackerWithPrevalence] = trackerDataProvider.trackerData.entities.values.compactMap { entity in
            guard let displayName = entity.displayName, let prevalence = entity.prevalence else {
                return nil
            }
            return TrackerWithPrevalence(name: displayName, prevalence: prevalence)
        }

        let topTrackersArray = trackers.sorted(by: { $0.prevalence > $1.prevalence }).prefix(100).map(\.name)
        Logger.privacyStats.debug("top tracker companies: \(topTrackersArray)")
        topCompanies = Set(topTrackersArray)
    }

    private func loadCurrentStats() async {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<([String: Int], Date)?, Never>) in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let privacyStatsEntity = PrivacyStatsUtils.loadStats(in: context)
                currentStatsObject = privacyStatsEntity
                Logger.privacyStats.debug("Loaded stats \(privacyStatsEntity.timestamp) \(privacyStatsEntity.blockedTrackersDictionary)")
                continuation.resume(returning: (privacyStatsEntity.blockedTrackersDictionary, privacyStatsEntity.timestamp))
            }
        }
        if let (blockedTrackersDictionary, timestamp) = result {
            await currentStatsActor.set(blockedTrackersDictionary, for: timestamp)
        }
    }

    @objc private func applicationWillTerminate(_: Notification) {
        let condition = RunLoop.ResumeCondition()
        Task {
            if let timestamp = await currentStatsActor.timestamp {
                await commitChanges(await currentStatsActor.trackers, timestamp: timestamp)
            }
            condition.resolve()
        }
        // Run the loop until changes are saved
        RunLoop.current.run(until: condition)
    }
}
