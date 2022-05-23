
import Foundation

struct ResponseHandler: ResponseHandling {

    let persistence: LocalDataPersisting
    let dataLastUpdated: DataLastUpdatedPersisting
    let crypter: Crypting

    func handleUpdates(_ updates: [String : Any]) async throws {
        
        var events = [SyncEvent]()
        var bookmarksLastUpdated: String?

        try updates.forEach { key, value in
            guard let dict = value as? [String: Any],
                  let entries = dict["entries"] as? [[String: Any]]
            else { return }

            switch key {
            case "bookmarks": bookmarksLastUpdated = dict["last_modified"] as? String
            default: break
            }

            events += try syncEventsFromEntries(entries, key)
        }

        try await persistence.persist(events)

        if let bookmarksLastUpdated = bookmarksLastUpdated {
            dataLastUpdated.bookmarksUpdated(bookmarksLastUpdated)
        }

    }

    private func folderFrom(_ entry: [String: Any]) throws -> Folder? {
        guard let id = entry["id"] as? String,
              let encryptedTitle = entry["title"] as? String
        else { return nil }

        let nextItemId = entry["next_item"] as? String
        let parent = entry["parent"] as? String

        let title = try crypter.base64DecodeAndDecrypt(encryptedTitle)

        return Folder(id: id, title: title, nextItem: nextItemId, parent: parent)
    }

    private func siteFrom(_ entry: [String: Any]) throws -> SavedSite? {

        guard let id = entry["id"] as? String,
              let encryptedTitle = entry["title"] as? String,
              let encryptedUrl = entry["url"] as? String
        else { return nil }

        let isFavorite =  entry["is_favorite"] as? Bool ?? false
        let nextFavorite = entry["next_favorite"] as? String
        let nextItemId = entry["next_item"] as? String
        let parent = entry["parent"] as? String

        let title = try crypter.base64DecodeAndDecrypt(encryptedTitle)
        let url = try crypter.base64DecodeAndDecrypt(encryptedUrl)

        return SavedSite(id: id, title: title, url: url, isFavorite: isFavorite, nextFavorite: nextFavorite, nextItem: nextItemId, parent: parent)
    }

    private func syncEventsFromEntries(_ entries: [[String : Any]], _ dataType: String) throws -> [SyncEvent] {
        var events = [SyncEvent]()

        try entries.forEach { entry in
            guard let id = entry["id"] as? String,
                  let type = entry["type"] as? String
            else { return } // TODO log/throw?

            let deleted = entry["deleted"] as? Int == 1

            switch dataType {

            case "bookmarks" where deleted:
                events.append(.bookmarkDeleted(id: id))

            case "bookmarks" where type == "bookmark":
                if let site = try siteFrom(entry) {
                    events.append(.bookmarkUpdated(site))
                } else {
                    assertionFailure("Unable to create bookmark from entry")
                }

            case "bookmarks" where type == "folder":
                if let folder = try folderFrom(entry) {
                    events.append(.bookmarkFolderUpdated(folder))
                } else {
                    assertionFailure("Unable to create bookmark folder from entry")
                }

            default: break

            }
        }
        return events
    }
}
