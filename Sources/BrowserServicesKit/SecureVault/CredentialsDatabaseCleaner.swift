//
//  CredentialsDatabaseCleaner.swift
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
import GRDB
import SecureStorage

public struct CredentialsCleanupError: Error {
    public let cleanupError: Error

    public static let syncActive: CredentialsCleanupError = .init(cleanupError: CredentialsCleanupCancelledError())
}

public struct CredentialsCleanupCancelledError: Error {}

public final class CredentialsDatabaseCleaner {

    public var isSyncActive: () -> Bool = { false }

    public convenience init(
        secureVaultFactory: AutofillVaultFactory,
        secureVaultErrorReporter: SecureVaultErrorReporting,
        errorEvents: EventMapping<CredentialsCleanupError>?,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.init(
            secureVaultFactory: secureVaultFactory,
            secureVaultErrorReporter: secureVaultErrorReporter,
            errorEvents: errorEvents,
            log: log(),
            removeSyncMetadataPendingDeletion: Self.removeSyncMetadataPendingDeletion(in:)
        )
    }

    init(
        secureVaultFactory: AutofillVaultFactory,
        secureVaultErrorReporter: SecureVaultErrorReporting,
        errorEvents: EventMapping<CredentialsCleanupError>?,
        log: @escaping @autoclosure () -> OSLog = .disabled,
        removeSyncMetadataPendingDeletion: @escaping ((Database) throws -> Int)
    ) {
        self.secureVaultFactory = secureVaultFactory
        self.secureVaultErrorReporter = secureVaultErrorReporter
        self.errorEvents = errorEvents
        self.getLog = log
        self.removeSyncMetadataPendingDeletion = removeSyncMetadataPendingDeletion

        cleanupCancellable = triggerSubject
            .receive(on: workQueue)
            .sink { [weak self] _ in
                self?.removeSyncableCredentialsMetadataPendingDeletion()
            }
    }

    public func scheduleRegularCleaning() {
        cancelCleaningSchedule()
        scheduleCleanupCancellable = Timer.publish(every: Const.cleanupInterval, on: .main, in: .default)
            .sink { [weak self] _ in
                self?.triggerSubject.send()
            }
    }

    public func cancelCleaningSchedule() {
        scheduleCleanupCancellable?.cancel()
    }

    public func cleanUpDatabaseNow() {
        triggerSubject.send()
    }

    func removeSyncableCredentialsMetadataPendingDeletion() {
        guard !isSyncActive() else {
            errorEvents?.fire(.syncActive)
            return
        }

        var cleanupError: Error?
        var saveAttemptsLeft = Const.maxContextSaveRetries

        do {
            let secureVault = try secureVaultFactory.makeVault(errorReporter: secureVaultErrorReporter)

            while true {
                do {
                    var numberOfDeletedEntries: Int = 0
                    try secureVault.inDatabaseTransaction { database in
                        numberOfDeletedEntries = try self.removeSyncMetadataPendingDeletion(database)
                    }
                    if numberOfDeletedEntries == 0 {
                        os_log(.debug, log: log, "No syncable credentials metadata pending deletion")
                    } else {
                        os_log(.debug, log: log, "Successfully purged %{public}d sync credentials metadata", numberOfDeletedEntries)
                    }
                    break
                } catch {
                    if case SecureStorageError.databaseError(let cause) = error, let databaseError = cause as? DatabaseError {
                        switch databaseError {
                        case .SQLITE_BUSY, .SQLITE_LOCKED:
                            saveAttemptsLeft -= 1
                            if saveAttemptsLeft == 0 {
                                cleanupError = error
                                break
                            }
                        default:
                            throw error
                        }
                    } else {
                        throw error
                    }
                }
            }
        } catch {
            cleanupError = error
        }

        if let cleanupError {
            errorEvents?.fire(.init(cleanupError: cleanupError))
        }
    }

    private static func removeSyncMetadataPendingDeletion(in database: Database) throws -> Int {
        let deletedRecords = try SecureVaultModels.SyncableCredentialsRecord
            .filter(SecureVaultModels.SyncableCredentialsRecord.Columns.objectId == nil)
            .deleteAndFetchAll(database)
        return deletedRecords.count
    }

    enum Const {
        static let cleanupInterval: TimeInterval = 24 * 3600
        static let maxContextSaveRetries = 5
    }

    private let errorEvents: EventMapping<CredentialsCleanupError>?
    private let secureVaultFactory: AutofillVaultFactory
    private let secureVaultErrorReporter: SecureVaultErrorReporting
    private let triggerSubject = PassthroughSubject<Void, Never>()
    private let workQueue = DispatchQueue(label: "CredentialsDatabaseCleaner queue", qos: .userInitiated)

    private var cleanupCancellable: AnyCancellable?
    private var scheduleCleanupCancellable: AnyCancellable?
    private let removeSyncMetadataPendingDeletion: (Database) throws -> Int

    private let getLog: () -> OSLog
    private var log: OSLog {
        getLog()
    }
}
