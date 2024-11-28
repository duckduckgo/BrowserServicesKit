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
import Common
import Foundation
import os.log
import Persistence
import TrackerRadarKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/**
 * Errors that may be reported by `PrivacyStats`.
 */
public enum PrivacyStatsError: CustomNSError {
    case failedToFetchPrivacyStatsSummary(Error)
    case failedToStorePrivacyStats(Error)
    case failedToLoadCurrentPrivacyStats(Error)

    public static let errorDomain: String = "PrivacyStatsError"

    public var errorCode: Int {
        switch self {
        case .failedToFetchPrivacyStatsSummary:
            return 1
        case .failedToStorePrivacyStats:
            return 2
        case .failedToLoadCurrentPrivacyStats:
            return 3
        }
    }

    public var underlyingError: Error {
        switch self {
        case .failedToFetchPrivacyStatsSummary(let error),
                .failedToStorePrivacyStats(let error),
                .failedToLoadCurrentPrivacyStats(let error):
            return error
        }
    }
}

public protocol PrivacyStatsDatabaseProviding {
    func initializeDatabase() -> CoreDataDatabase
}

public protocol PrivacyStatsCollecting {
    func recordBlockedTracker(_ name: String) async

    var statsUpdatePublisher: AnyPublisher<Void, Never> { get }
    func fetchPrivacyStats() async -> [String: Int64]
    func clearPrivacyStats() async
}

public final class PrivacyStats: PrivacyStatsCollecting {

    public static let bundle = Bundle.module

    public let statsUpdatePublisher: AnyPublisher<Void, Never>

    private let db: CoreDataDatabase
    private let context: NSManagedObjectContext
    private var currentPack: CurrentPack?
    private let statsUpdateSubject = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    private let errorEvents: EventMapping<PrivacyStatsError>?

    public init(databaseProvider: PrivacyStatsDatabaseProviding, errorEvents: EventMapping<PrivacyStatsError>? = nil) {
        self.db = databaseProvider.initializeDatabase()
        self.context = db.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "PrivacyStats")
        self.errorEvents = errorEvents

        statsUpdatePublisher = statsUpdateSubject.eraseToAnyPublisher()
        currentPack = .init(pack: initializeCurrentPack())

        currentPack?.commitChangesPublisher
            .sink { [weak self] pack in
                Task {
                    await self?.commitChanges(pack)
                }
            }
            .store(in: &cancellables)

#if os(iOS)
        let notificationName = UIApplication.willTerminateNotification
#elseif os(macOS)
        let notificationName = NSApplication.willTerminateNotification
#endif
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: notificationName, object: nil)

    }

    public func recordBlockedTracker(_ name: String) async {
        await currentPack?.recordBlockedTracker(name)
    }

    public func fetchPrivacyStats() async -> [String: Int64] {
        return await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume(returning: [:])
                    return
                }
                do {
                    let stats = try PrivacyStatsUtils.load7DayStats(in: context)
                    continuation.resume(returning: stats)
                } catch {
                    errorEvents?.fire(.failedToFetchPrivacyStatsSummary(error))
                    continuation.resume(returning: [:])
                }
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
                    errorEvents?.fire(.failedToFetchPrivacyStatsSummary(error))
                }
                continuation.resume()
            }
        }
        await currentPack?.resetPack()
    }

    // MARK: - Private

    private func commitChanges(_ pack: PrivacyStatsPack) async {
        await withCheckedContinuation { continuation in
            context.perform { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                do {
                    let statsObjects = try PrivacyStatsUtils.fetchOrInsertCurrentStats(for: Set(pack.trackers.keys), in: context)
                    statsObjects.forEach { stats in
                        if let count = pack.trackers[stats.companyName] {
                            stats.count = count
                        }
                    }

                    // Delete outdated packs if the pack we're storing is from a previous day.
                    // This means that it's a new day and we may have outdated packs.
                    if pack.timestamp < Date.currentPrivacyStatsPackTimestamp {
                        PrivacyStatsUtils.deleteOutdatedPacks(in: context)
                    }

                    guard context.hasChanges else {
                        continuation.resume()
                        return
                    }

                    try context.save()
                    Logger.privacyStats.debug("Saved stats \(pack.timestamp) \(pack.trackers)")
                    statsUpdateSubject.send()
                } catch {
                    Logger.privacyStats.error("Save error: \(error)")
                    errorEvents?.fire(.failedToStorePrivacyStats(error))
                }
                continuation.resume()
            }
        }
    }

    private func initializeCurrentPack() -> PrivacyStatsPack {
        var pack: PrivacyStatsPack?
        context.performAndWait {
            let timestamp = Date.currentPrivacyStatsPackTimestamp
            do {
                let currentDayStats = try PrivacyStatsUtils.loadCurrentDayStats(in: context)
                Logger.privacyStats.debug("Loaded stats \(timestamp) \(currentDayStats)")
                pack = PrivacyStatsPack(timestamp: timestamp, trackers: currentDayStats)

                PrivacyStatsUtils.deleteOutdatedPacks(in: context)
                try context.save()
            } catch {
                Logger.privacyStats.error("Faild to load current stats: \(error)")
                errorEvents?.fire(.failedToLoadCurrentPrivacyStats(error))
            }
        }
        return pack ?? PrivacyStatsPack(timestamp: Date.currentPrivacyStatsPackTimestamp)
    }

    @objc private func applicationWillTerminate(_: Notification) {
        let condition = RunLoop.ResumeCondition()
        Task {
            if let pack = await currentPack?.pack {
                await commitChanges(pack)
            }
            condition.resolve()
        }
        // Run the loop until changes are saved
        RunLoop.current.run(until: condition)
    }
}
