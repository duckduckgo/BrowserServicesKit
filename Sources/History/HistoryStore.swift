//
//  HistoryStore.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Common
import Foundation
import CoreData
import Combine
import Persistence

final public class HistoryStore: HistoryStoring {

    public enum HistoryStoreEvents {

        case removeFailed
        case reloadFailed
        case cleanEntriesFailed
        case cleanVisitsFailed
        case saveFailed
        case insertVisitFailed
        case removeVisitsFailed

    }

    let context: NSManagedObjectContext
    let eventMapper: EventMapping<HistoryStoreEvents>

    public init(context: NSManagedObjectContext, eventMapper: EventMapping<HistoryStoreEvents>) {
        self.context = context
        self.eventMapper = eventMapper
    }

    enum HistoryStoreError: Error {
        case storeDeallocated
        case savingFailed
    }

    public func removeEntries(_ entries: [HistoryEntry]) -> Future<Void, Error> {
        return Future { [weak self] promise in
            self?.context.perform {
                guard let self = self else {
                    promise(.failure(HistoryStoreError.storeDeallocated))
                    return
                }

                do {
                    let identifiers = entries.map { $0.identifier }

                    try self.context.applyChangesAndSave { context in
                        try self.markForDeletion(identifiers, in: context)
                    }
                    promise(.success(()))
                } catch {
                    self.eventMapper.fire(.removeFailed, error: error)
                    promise(.failure(error))
                }
            }
        }
    }

    public func cleanOld(until date: Date) -> Future<BrowsingHistory, Error> {
        return Future { [weak self] promise in
            self?.context.perform {
                guard let self = self else {
                    promise(.failure(HistoryStoreError.storeDeallocated))
                    return
                }

                do {
                    try self.context.applyChangesAndSave { context in
                        let deleteRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
                        deleteRequest.predicate = NSPredicate(format: "lastVisit < %@", date as NSDate)

                        let itemsToBeDeleted = try context.fetch(deleteRequest)
                        for item in itemsToBeDeleted {
                            context.delete(item)
                        }
                    }
                } catch {
                    self.eventMapper.fire(.cleanEntriesFailed, error: error)
                    promise(.failure(error))
                    return
                }

                do {
                    try self.context.applyChangesAndSave { context in
                        let visitDeleteRequest = PageVisitManagedObject.fetchRequest()
                        visitDeleteRequest.predicate = NSPredicate(format: "date < %@", date as NSDate)

                        let itemsToBeDeleted = try context.fetch(visitDeleteRequest)
                        for item in itemsToBeDeleted {
                            context.delete(item)
                        }
                    }
                } catch {
                    self.eventMapper.fire(.cleanVisitsFailed, error: error)
                    promise(.failure(error))
                    return
                }

                let reloadResult = self.reload(self.context)
                promise(reloadResult)
            }
        }
    }

    private func markForDeletion(_ identifiers: [UUID], in context: NSManagedObjectContext) throws {
        // To avoid long predicate, execute multiple times
        let chunkedIdentifiers = identifiers.chunked(into: 100)

        for identifiers in chunkedIdentifiers {
            let deleteRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
            let predicates = identifiers.map({ NSPredicate(format: "identifier == %@", argumentArray: [$0]) })
            deleteRequest.predicate = NSCompoundPredicate(type: .or, subpredicates: predicates)

            let entriesToDelete = try context.fetch(deleteRequest)
            for entry in entriesToDelete {
                context.delete(entry)
            }
            os_log("%d items cleaned from history", log: .history, entriesToDelete.count)
        }
    }

    private func reload(_ context: NSManagedObjectContext) -> Result<BrowsingHistory, Error> {
        let fetchRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let historyEntries = try context.fetch(fetchRequest)
            os_log("%d entries loaded from history", log: .history, historyEntries.count)
            let history = BrowsingHistory(historyEntries: historyEntries)
            return .success(history)
        } catch {
            eventMapper.fire(.reloadFailed, error: error)
            return .failure(error)
        }
    }

    public func save(entry: HistoryEntry) -> Future<[(id: Visit.ID, date: Date)], Error> {
        return Future { [weak self] promise in
            self?.context.perform { [weak self] in
                guard let self = self else {
                    promise(.failure(HistoryStoreError.storeDeallocated))
                    return
                }

                // Check for existence
                let fetchRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
                fetchRequest.returnsObjectsAsFaults = false
                fetchRequest.fetchLimit = 1
                fetchRequest.predicate = NSPredicate(format: "identifier == %@", entry.identifier as CVarArg)
                let fetchedObjects: [BrowsingHistoryEntryManagedObject]
                do {
                    fetchedObjects = try self.context.fetch(fetchRequest)
                } catch {
                    eventMapper.fire(.saveFailed, error: error)
                    promise(.failure(error))
                    return
                }

                assert(fetchedObjects.count <= 1, "More than 1 history entry with the same identifier")

                // Apply changes

                do {
                    var visitMOs = [PageVisitManagedObject]()

                    try self.context.applyChangesAndSave { context in
                        let historyEntryManagedObject: BrowsingHistoryEntryManagedObject
                        if let fetchedObject = fetchedObjects.first {
                            // Update existing
                            fetchedObject.update(with: entry)
                            historyEntryManagedObject = fetchedObject
                        } else {
                            // Add new
                            let insertedObject = NSEntityDescription.insertNewObject(forEntityName: BrowsingHistoryEntryManagedObject.entityName, into: self.context)
                            guard let historyEntryMO = insertedObject as? BrowsingHistoryEntryManagedObject else {
                                promise(.failure(HistoryStoreError.savingFailed))
                                return
                            }
                            historyEntryMO.update(with: entry, afterInsertion: true)
                            historyEntryManagedObject = historyEntryMO
                        }

                        visitMOs = self.insertNewVisits(of: entry,
                                                        into: historyEntryManagedObject,
                                                        context: self.context)
                    }

                    let result = visitMOs.compactMap {
                        if let date = $0.date {
                            return (id: $0.objectID.uriRepresentation(), date: date)
                        } else {
                            return nil
                        }
                    }
                    promise(.success(result))

                } catch {
                    eventMapper.fire(.saveFailed, error: error)
                    promise(.failure(HistoryStoreError.savingFailed))
                }
            }
        }
    }

    private func insertNewVisits(of historyEntry: HistoryEntry,
                                 into historyEntryManagedObject: BrowsingHistoryEntryManagedObject,
                                 context: NSManagedObjectContext) -> [PageVisitManagedObject] {
        historyEntry.visits
            .filter {
                $0.savingState == .initialized
            }
            .map {
                $0.savingState = .saved
                let visitMO = PageVisitManagedObject(context: context)
                visitMO.update(with: $0, historyEntryManagedObject: historyEntryManagedObject)
                return visitMO
            }
    }

    public func removeVisits(_ visits: [Visit]) -> Future<Void, Error> {
        return Future { [weak self] promise in
            self?.context.perform {
                guard let self = self else {
                    promise(.failure(HistoryStoreError.storeDeallocated))
                    return
                }

                do {
                    try self.context.applyChangesAndSave { context in
                        try self.markForDeletion(visits, context: context)
                    }

                    promise(.success(()))
                } catch {
                    self.eventMapper.fire(.removeVisitsFailed, error: error)
                    promise(.failure(error))
                }
            }
        }
    }

    private func markForDeletion(_ visits: [Visit], context: NSManagedObjectContext) throws {
        // To avoid long predicate, execute multiple times
        let chunkedVisits = visits.chunked(into: 100)

        for visits in chunkedVisits {
            let deleteRequest = PageVisitManagedObject.fetchRequest()
            let predicates = visits.compactMap({ (visit: Visit) -> NSPredicate? in
                guard let historyEntry = visit.historyEntry else {
                    assertionFailure("No history entry")
                    return nil
                }

                return NSPredicate(format: "historyEntry.identifier == %@ && date == %@", argumentArray: [historyEntry.identifier, visit.date])
            })
            deleteRequest.predicate = NSCompoundPredicate(type: .or, subpredicates: predicates)

            let visitsToDelete = try self.context.fetch(deleteRequest)

            for visit in visitsToDelete {
                context.delete(visit)
            }
        }
    }

}

fileprivate extension BrowsingHistory {

    init(historyEntries: [BrowsingHistoryEntryManagedObject]) {
        self = historyEntries.reduce(into: BrowsingHistory(), {
            if let historyEntry = HistoryEntry(historyEntryMO: $1) {
                $0.append(historyEntry)
            }
        })
    }

}

fileprivate extension HistoryEntry {

    convenience init?(historyEntryMO: BrowsingHistoryEntryManagedObject) {
        guard let url = historyEntryMO.url,
              let identifier = historyEntryMO.identifier,
              let lastVisit = historyEntryMO.lastVisit else {
            assertionFailure("HistoryEntry: Failed to init HistoryEntry from BrowsingHistoryEntryManagedObject")
            return nil
        }

        let title = historyEntryMO.title
        let numberOfTotalVisits = historyEntryMO.numberOfTotalVisits
        let numberOfTrackersBlocked = historyEntryMO.numberOfTrackersBlocked
        let blockedTrackingEntities = historyEntryMO.blockedTrackingEntities ?? ""
        let visits = Set(historyEntryMO.visits?.allObjects.compactMap {
            Visit(visitMO: $0 as? PageVisitManagedObject)
        } ?? [])

        assert(Dictionary(grouping: visits, by: \.date).filter({ $1.count > 1 }).isEmpty, "Duplicate of visit stored")

        self.init(identifier: identifier,
                  url: url,
                  title: title,
                  failedToLoad: historyEntryMO.failedToLoad,
                  numberOfTotalVisits: Int(numberOfTotalVisits),
                  lastVisit: lastVisit,
                  visits: visits,
                  numberOfTrackersBlocked: Int(numberOfTrackersBlocked),
                  blockedTrackingEntities: Set<String>(blockedTrackingEntities.components(separatedBy: "|")),
                  trackersFound: historyEntryMO.trackersFound)

        visits.forEach { visit in
            visit.historyEntry = self
        }
    }

}

fileprivate extension BrowsingHistoryEntryManagedObject {

    func update(with entry: HistoryEntry, afterInsertion: Bool = false) {
        if afterInsertion {
            identifier = entry.identifier
            url = entry.url
        }

        assert(url == entry.url, "URLs don't match")
        assert(identifier == entry.identifier, "Identifiers don't match")

        url = entry.url
        if let title = entry.title, !title.isEmpty {
            self.title = title
        }
        numberOfTotalVisits = Int64(entry.numberOfTotalVisits)
        lastVisit = entry.lastVisit
        failedToLoad = entry.failedToLoad
        numberOfTrackersBlocked = Int64(entry.numberOfTrackersBlocked)
        blockedTrackingEntities = entry.blockedTrackingEntities.isEmpty ? "" : entry.blockedTrackingEntities.joined(separator: "|")
        trackersFound = entry.trackersFound
    }

}

private extension PageVisitManagedObject {

    func update(with visit: Visit, historyEntryManagedObject: BrowsingHistoryEntryManagedObject) {
        date = visit.date
        historyEntry = historyEntryManagedObject
    }

}

private extension Visit {

    convenience init?(visitMO: PageVisitManagedObject?) {
        guard let visitMO = visitMO,
                let date = visitMO.date else {
            assertionFailure("Bad type or date is nil")
            return nil
        }

        let id = visitMO.objectID.uriRepresentation()
        self.init(date: date, identifier: id)
        savingState = .saved
    }

}

private extension NSManagedObject {

    static var entityName: String {
        String(describing: self)
    }

}
