//
//  RemoteMessagingStore.swift
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
import Combine
import Common
import CoreData
import BrowserServicesKit
import Persistence

public enum RemoteMessagingStoreError: Error {
    case saveConfigFailed
    case invalidateConfigFailed
    case updateMessageShownFailed
    case saveMessageFailed
    case updateMessageStatusFailed
    case deleteScheduledMessageFailed
}

public final class RemoteMessagingStore: RemoteMessagingStoring {

    public struct Notifications {
        static public let remoteMessagesDidChange = Notification.Name("com.duckduckgo.app.RemoteMessagesDidChange")
    }

    private enum RemoteMessageStatus: Int16 {
        case scheduled
        case dismissed
        case done
    }

    public enum Constants {
        public static let privateContextName = "RemoteMessaging"
    }

    let database: CoreDataDatabase
    let notificationCenter: NotificationCenter
    let remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding

    public init(
        database: CoreDataDatabase,
        notificationCenter: NotificationCenter = .default,
        errorEvents: EventMapping<RemoteMessagingStoreError>?,
        remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding,
        log: @escaping @autoclosure () -> OSLog = .disabled
    ) {
        self.database = database
        self.notificationCenter = notificationCenter
        self.errorEvents = errorEvents
        self.remoteMessagingAvailabilityProvider = remoteMessagingAvailabilityProvider
        self.getLog = log

        featureFlagDisabledCancellable = remoteMessagingAvailabilityProvider.isRemoteMessagingAvailablePublisher
            .map { !$0 }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.deleteScheduledMessagesIfNeeded()
            }
    }

    public func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            os_log(
                "Remote messaging feature flag is disabled, skipping saving processed version: %d",
                log: log,
                type: .debug,
                processorResult.version
            )
            return
        }
        os_log("Remote messaging config - save processed version: %d", log: log, type: .debug, processorResult.version)

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        saveRemoteMessagingConfig(withVersion: processorResult.version, in: context)

        if let remoteMessage = processorResult.message {
            deleteScheduledRemoteMessages(in: context)
            save(remoteMessage: remoteMessage, in: context)

        } else {
            deleteScheduledRemoteMessages(in: context)
        }
        notificationCenter.post(name: Notifications.remoteMessagesDidChange, object: nil)
    }

    private func deleteScheduledMessagesIfNeeded() {
        guard fetchScheduledRemoteMessage() != nil else {
            return
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)

        invalidateRemoteMessagingConfigs(in: context)
        deleteScheduledRemoteMessages(in: context)
        notificationCenter.post(name: Notifications.remoteMessagesDidChange, object: nil)
    }

    private let errorEvents: EventMapping<RemoteMessagingStoreError>?
    private var featureFlagDisabledCancellable: AnyCancellable?

    private let getLog: () -> OSLog
    private var log: OSLog {
        getLog()
    }
}

// MARK: - RemoteMessagingConfigManagedObject Public Interface

extension RemoteMessagingStore {

    public func fetchRemoteMessagingConfig() -> RemoteMessagingConfig? {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return nil
        }

        var config: RemoteMessagingConfig?
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            let fetchRequest = RemoteMessagingConfigManagedObject.fetchRequest()
            fetchRequest.fetchLimit = 1
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "version", ascending: false)]

            guard let results = try? context.fetch(fetchRequest) else {
                return
            }
            if let remoteMessagingConfigManagedObject = results.first {
                config = RemoteMessagingConfig(remoteMessagingConfigManagedObject)
            }
        }

        return config
    }

}

// MARK: - RemoteMessagingConfigManagedObject Private Interface

extension RemoteMessagingStore {

    private func saveRemoteMessagingConfig(withVersion version: Int64, in context: NSManagedObjectContext) {
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessagingConfigManagedObject> = RemoteMessagingConfigManagedObject.fetchRequest()
            fetchRequest.fetchLimit = 1
            fetchRequest.predicate = NSPredicate(format: "version == %lld", version)

            if let results = try? context.fetch(fetchRequest), let result = results.first {
                result.evaluationTimestamp = Date()
                result.invalidate = false
            } else {
                let remoteMessagingConfigManagedObject = RemoteMessagingConfigManagedObject(context: context)
                remoteMessagingConfigManagedObject.version = NSNumber(value: version)
                remoteMessagingConfigManagedObject.evaluationTimestamp = Date()
                remoteMessagingConfigManagedObject.invalidate = false
            }

            do {
                try context.save()
            } catch {
                errorEvents?.fire(.saveConfigFailed, error: error)
                os_log("Failed to save remote messaging config: %@",
                       log: log,
                       type: .error, error.localizedDescription)
            }
        }
    }

    private func invalidateRemoteMessagingConfigs(in context: NSManagedObjectContext) {
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessagingConfigManagedObject> = RemoteMessagingConfigManagedObject.fetchRequest()
            fetchRequest.returnsObjectsAsFaults = false

            guard let results = try? context.fetch(fetchRequest) else { return }

            results.forEach { $0.invalidate = true }

            do {
                try context.save()
            } catch {
                errorEvents?.fire(.invalidateConfigFailed, error: error)
                os_log("Failed to save remote messaging config entity invalidate: %@",
                       log: log,
                       type: .error, error.localizedDescription)
            }
        }
    }
}

// MARK: - RemoteMessageManagedObject Public Interface

extension RemoteMessagingStore {

    public func fetchScheduledRemoteMessage() -> RemoteMessageModel? {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return nil
        }

        var scheduledRemoteMessage: RemoteMessageModel?
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "status == %i", RemoteMessageStatus.scheduled.rawValue)
            fetchRequest.returnsObjectsAsFaults = false

            guard let results = try? context.fetch(fetchRequest) else { return }

            for remoteMessageManagedObject in results {
                guard let message = remoteMessageManagedObject.message,
                      let remoteMessage = RemoteMessageMapper.fromString(message),
                      let id = remoteMessageManagedObject.id
                else {
                    continue
                }

                scheduledRemoteMessage = RemoteMessageModel(id: id, content: remoteMessage.content, matchingRules: [], exclusionRules: [])
                break
            }
        }
        return scheduledRemoteMessage
    }

    public func fetchRemoteMessage(withID id: String) -> RemoteMessageModel? {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return nil
        }

        var remoteMessage: RemoteMessageModel?
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            fetchRequest.returnsObjectsAsFaults = false

            guard let results = try? context.fetch(fetchRequest) else { return }

            for remoteMessageManagedObject in results {
                guard let message = remoteMessageManagedObject.message,
                      let remoteMessageMapped = RemoteMessageMapper.fromString(message),
                      let id = remoteMessageManagedObject.id
                else {
                    continue
                }

                remoteMessage = RemoteMessageModel(id: id, content: remoteMessageMapped.content, matchingRules: [], exclusionRules: [])
                break
            }
        }
        return remoteMessage
    }

    public func hasShownRemoteMessage(withID id: String) -> Bool {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return false
        }

        var shown: Bool = true
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.fetchLimit = 1
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)

            guard let results = try? context.fetch(fetchRequest) else { return }

            if let result = results.first {
                shown = result.shown
            }
        }
        return shown
    }

    public func hasDismissedRemoteMessage(withID id: String) -> Bool {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return false
        }

        var dismissed: Bool = true
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.fetchLimit = 1
            fetchRequest.predicate = NSPredicate(format: "status == %i", RemoteMessageStatus.dismissed.rawValue)

            guard let results = try? context.fetch(fetchRequest) else { return }

            if results.first != nil {
                dismissed = true
            }
        }
        return dismissed
    }

    public func dismissRemoteMessage(withID id: String) {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            updateRemoteMessage(withID: id, toStatus: .dismissed, in: context)
            invalidateRemoteMessagingConfigs(in: context)
        }
    }

    public func fetchDismissedRemoteMessageIDs() -> [String] {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return []
        }

        var dismissedMessageIds: [String] = []
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "status == %i", RemoteMessageStatus.dismissed.rawValue)
            fetchRequest.returnsObjectsAsFaults = false

            do {
                let results = try context.fetch(fetchRequest)
                dismissedMessageIds = results.compactMap { $0.id }
            } catch {
                os_log("Failed to fetch dismissed remote messages: %@", log: log, type: .error, error.localizedDescription)
            }
        }
        return dismissedMessageIds
    }

    public func updateRemoteMessage(withID id: String, asShown shown: Bool) {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            fetchRequest.returnsObjectsAsFaults = false

            guard let results = try? context.fetch(fetchRequest) else { return }

            results.forEach { $0.shown = shown }
            do {
                try context.save()
            } catch {
                errorEvents?.fire(.updateMessageShownFailed, error: error)
                os_log("Failed to save message update as shown", log: log, type: .error)
            }
        }
    }

    public func resetRemoteMessages() {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            return
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: Constants.privateContextName)
        context.performAndWait {
            context.deleteAll(entityDescriptions: [
                RemoteMessageManagedObject.entity(in: context),
                RemoteMessagingConfigManagedObject.entity(in: context)
            ])

            do {
                try context.save()
            } catch {
                os_log("Failed to reset remote messages", log: log, type: .error)
            }
        }
        notificationCenter.post(name: Notifications.remoteMessagesDidChange, object: nil)
    }
}

// MARK: - RemoteMessageManagedObject Private Interface

extension RemoteMessagingStore {

    private func save(remoteMessage: RemoteMessageModel, in context: NSManagedObjectContext) {
        context.performAndWait {
            let remoteMessageManagedObject = RemoteMessageManagedObject(context: context)

            remoteMessageManagedObject.id = remoteMessage.id
            remoteMessageManagedObject.message = RemoteMessageMapper.toString(remoteMessage) ?? ""
            remoteMessageManagedObject.status = NSNumber(value: RemoteMessageStatus.scheduled.rawValue)
            remoteMessageManagedObject.shown = false

            do {
                try context.save()
            } catch {
                errorEvents?.fire(.saveMessageFailed, error: error)
                os_log("Failed to save remote message entity: %@", log: log, type: .error, error.localizedDescription)
            }
        }
    }

    private func updateRemoteMessage(withID id: String, toStatus status: RemoteMessageStatus, in context: NSManagedObjectContext) {
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            fetchRequest.returnsObjectsAsFaults = false

            guard let results = try? context.fetch(fetchRequest) else { return }

            results.forEach { $0.status = NSNumber(value: status.rawValue) }

            do {
                try context.save()
            } catch {
                errorEvents?.fire(.updateMessageStatusFailed, error: error)
                os_log("Error saving updateMessageStatus", log: log, type: .error)
            }
        }
    }

    private func deleteScheduledRemoteMessages(in context: NSManagedObjectContext) {
        context.performAndWait {
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            fetchRequest.returnsObjectsAsFaults = false
            fetchRequest.predicate = NSPredicate(format: "status == %i", RemoteMessageStatus.scheduled.rawValue)

            let results = try? context.fetch(fetchRequest)
            results?.forEach {
                context.delete($0)
            }
            do {
                try context.save()
            } catch {
                errorEvents?.fire(.deleteScheduledMessageFailed, error: error)
                os_log("Error deleting scheduled remote messages", log: log, type: .error)
            }
        }
    }
}

// MARK: - MessageMapper

private struct RemoteMessageMapper {

    static func toString(_ remoteMessage: RemoteMessageModel?) -> String? {
        guard let message = remoteMessage,
              let encodedData = try? JSONEncoder().encode(message),
              let jsonString = String(data: encodedData, encoding: .utf8) else { return nil }
        return jsonString
    }

    static func fromString(_ payload: String) -> RemoteMessageModel? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RemoteMessageModel.self, from: data)
    }
}
