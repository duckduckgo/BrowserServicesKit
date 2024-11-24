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
    func recordBlockedTracker(_ name: String)
    var topCompanies: Set<String> { get }
    var currentStats: [String: Int] { get }

    var currentStatsPublisher: AnyPublisher<[String: Int], Never> { get }

    func fetchPrivacyStats() -> [String: Int]
}

public protocol TrackerDataProviding {
    var trackerData: TrackerData { get }
    var trackerDataUpdatesPublisher: AnyPublisher<Void, Never> { get }
}

public final class PrivacyStats: PrivacyStatsCollecting {

    public static let bundle = Bundle.module

    public let trackerDataProvider: TrackerDataProviding
    public private(set) var topCompanies: Set<String> = []

    @Published public private(set) var currentStats: [String: Int] = [:] // current pack
    public var currentStatsPublisher: AnyPublisher<[String: Int], Never> {
        $currentStats.dropFirst().eraseToAnyPublisher()
    }

    private var cancellables: Set<AnyCancellable> = []
    private let db: CoreDataDatabase
    private let context: NSManagedObjectContext

    // current pack timestamp
    private var currentTimestamp: Date?
    private var currentStatsObject: PrivacyStatsEntity?
    private let currentStatsLock = NSLock()

    private var commitTimer: Timer?

    private var cached7DayStats: [String: Int] = [:]
    private var cached7DayStatsLastFetchTimestamp: Date?

    public func recordBlockedTracker(_ name: String) {
        currentStatsLock.withLock {
            let timestamp = Date().startOfHour
            if timestamp != currentTimestamp {
                commitChanges()
                createNewStatsObject(for: timestamp)
            }

            let count = currentStats[name] ?? 0
            currentStats[name] = count + 1

            commitTimer?.invalidate()
            commitTimer = Timer.scheduledTimer(withTimeInterval: .seconds(1), repeats: false, block: { [weak self] _ in
                self?.commitChanges()
            })
        }
    }

    private func commitChanges() {
        context.performAndWait {
            currentStatsObject?.blockedTrackersDictionary = currentStats
            do {
                try context.save()
                Logger.privacyStats.debug("Saved stats \(String(reflecting: self.currentTimestamp)) \(self.currentStats)")
            } catch {
                Logger.privacyStats.error("Save error: \(error)")
            }
        }
    }

    public func fetchPrivacyStats() -> [String: Int] {
        let isCacheValid: Bool = {
            guard let cached7DayStatsLastFetchTimestamp else {
                return false
            }
            return Date.isSameHour(Date(), cached7DayStatsLastFetchTimestamp)
        }()
        if !isCacheValid {
            refresh7DayCache()
            deleteOldEntries()
        }
        return cached7DayStats.merging(currentStats, uniquingKeysWith: +).filter { topCompanies.contains($0.key) }
    }

    private func refresh7DayCache() {
        context.performAndWait {
            cached7DayStats = PrivacyStatsUtils.load7DayStats(in: context)
            cached7DayStatsLastFetchTimestamp = Date()
        }
    }

    private func deleteOldEntries() {
        context.perform {
            PrivacyStatsUtils.deleteOutdatedStats(in: self.context)
            if self.context.hasChanges {
                do {
                    try self.context.save()
                    Logger.privacyStats.debug("Deleted outdated entries")
                } catch {
                    Logger.privacyStats.error("Save error: \(error)")
                }
            }
        }
    }

    public init(databaseProvider: PrivacyStatsDatabaseProviding, trackerDataProvider: TrackerDataProviding) {
        self.db = databaseProvider.initializeDatabase()
        self.context = db.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "PrivacyStats")

        self.trackerDataProvider = trackerDataProvider
        trackerDataProvider.trackerDataUpdatesPublisher
            .sink { [weak self] in
                self?.refreshTopCompanies()
            }
            .store(in: &cancellables)
        refreshTopCompanies()
        loadCurrentStats()

#if os(iOS)
        let notificationName = UIApplication.willTerminateNotification
#elseif os(macOS)
        let notificationName = NSApplication.willTerminateNotification
#endif

        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: notificationName, object: nil)
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

    private func loadCurrentStats() {
        context.perform {
            self.currentStatsObject = PrivacyStatsUtils.loadStats(in: self.context)
            self.currentStatsLock.withLock {
                self.currentStats = self.currentStatsObject?.blockedTrackersDictionary ?? [:]
                self.currentTimestamp = self.currentStatsObject?.timestamp
                Logger.privacyStats.debug("Loaded stats \(String(reflecting: self.currentTimestamp)) \(self.currentStats)")
            }
        }
    }

    private func createNewStatsObject(for timestamp: Date) {
        context.performAndWait {
            currentStatsObject = PrivacyStatsEntity.make(timestamp: timestamp, context: context)
        }
        currentStats = [:]
        currentTimestamp = timestamp
    }

    @objc private func applicationWillTerminate(_: Notification) {
        currentStatsLock.withLock {
            commitChanges()
        }
    }
}
