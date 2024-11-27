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

    var statsUpdatePublisher: AnyPublisher<Void, Never> { get }
    func fetchPrivacyStats() async -> [String: Int64]
    func clearPrivacyStats() async
}

public protocol TrackerDataProviding {
    var trackerData: TrackerData { get }
    var trackerDataUpdatesPublisher: AnyPublisher<Void, Never> { get }
}

public final class PrivacyStats: PrivacyStatsCollecting {

    public static let bundle = Bundle.module

    public let trackerDataProvider: TrackerDataProviding
    public private(set) var topCompanies: Set<String> = []
    public let statsUpdatePublisher: AnyPublisher<Void, Never>

    private let db: CoreDataDatabase
    private let context: NSManagedObjectContext
    private let statsUpdateSubject = PassthroughSubject<Void, Never>()
    private var currentPack: CurrentPack
    private var cancellables: Set<AnyCancellable> = []

    public init(databaseProvider: PrivacyStatsDatabaseProviding, trackerDataProvider: TrackerDataProviding) {
        self.trackerDataProvider = trackerDataProvider
        self.db = databaseProvider.initializeDatabase()
        self.context = db.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "PrivacyStats")

        currentPack = CurrentPack()
        statsUpdatePublisher = statsUpdateSubject.eraseToAnyPublisher()

        trackerDataProvider.trackerDataUpdatesPublisher
            .sink { [weak self] in
                self?.refreshTopCompanies()
            }
            .store(in: &cancellables)

        refreshTopCompanies()
        Task {
            await loadCurrentPack()
            await currentPack.commitChangesPublisher
                .sink { [weak self] pack in
                    Task {
                        await self?.commitChanges(pack)
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
        await currentPack.recordBlockedTracker(name)
    }

    public func fetchPrivacyStats() async -> [String: Int64] {
        return await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume(returning: [:])
                    return
                }
                let stats = PrivacyStatsUtils.load7DayStats(in: context)
                continuation.resume(returning: stats)
            }
        }
    }

    public func clearPrivacyStats() async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                PrivacyStatsUtils.deleteAllStats(in: context)
                do {
                    try context.save()
                    Logger.privacyStats.debug("Deleted outdated entries")
                } catch {
                    Logger.privacyStats.error("Save error: \(error)")
                }
                continuation.resume()
            }
        }
        await loadCurrentPack()
    }

    // MARK: - Private

    private func commitChanges(_ pack: PrivacyStatsPack) async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                let statsObjects = PrivacyStatsUtils.fetchOrInsertCurrentPacks(for: Set(pack.trackers.keys), in: context)
                statsObjects.forEach { stats in
                    if let count = pack.trackers[stats.companyName] {
                        stats.count = count
                    }
                }

                guard context.hasChanges else {
                    continuation.resume()
                    return
                }

                do {
                    try context.save()
                    Logger.privacyStats.debug("Saved stats \(pack.timestamp) \(pack.trackers)")
                    statsUpdateSubject.send()
                } catch {
                    Logger.privacyStats.error("Save error: \(error)")
                }
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

                PrivacyStatsUtils.deleteOutdatedPacks(in: context)
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

    private func loadCurrentPack() async {
        let pack = await withCheckedContinuation { (continuation: CheckedContinuation<PrivacyStatsPack?, Never>) in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let currentPack = PrivacyStatsUtils.fetchCurrentPackStats(in: context)
                Logger.privacyStats.debug("Loaded stats \(currentPack.timestamp) \(currentPack.trackers)")
                continuation.resume(returning: currentPack)
            }
        }
        if let pack {
            await currentPack.updatePack(pack)
        }
    }

    @objc private func applicationWillTerminate(_: Notification) {
        let condition = RunLoop.ResumeCondition()
        Task {
            await commitChanges(currentPack.pack)
            condition.resolve()
        }
        // Run the loop until changes are saved
        RunLoop.current.run(until: condition)
    }
}
