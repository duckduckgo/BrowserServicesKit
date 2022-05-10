
import Foundation

struct ResponseHandler: ResponseHandling {

    let persistence: LocalDataPersisting
    let dataLastUpdated: DataLastUpdatedPersisting
    let crypter: Crypting

    func handleUpdates(_ updates: [String : Any]) async throws {
        var events = [SyncEvent]()
        var bookmarksLastUpdated: String?
        var favoritesLastUpdated: String?

        try updates.forEach { key, value in
            guard let dict = value as? [String: Any],
                  let entries = dict["entries"] as? [[String: Any]]
            else { return }

            switch key {
            case "bookmarks": bookmarksLastUpdated = dict["last_updated"] as? String
            case "favorites": favoritesLastUpdated = dict["last_updated"] as? String
            default: break
            }

            try entries.forEach { entry in
                guard let id = entry["id"] as? String,
                        let type = entry["type"] as? String
                else { return } // TODO log/throw?

                let deleted = entry["deleted"] as? Int == 1

                switch key {

                case "bookmarks" where deleted:
                    events.append(.bookmarkDeleted(id: id))

                case "bookmarks" where type == "bookmark":
                    if let site = try siteFrom(entry) {
                        events.append(.bookmarkUpdated(site))
                    } // TODO log this?

                case "bookmarks" where type == "folder":
                    if let folder = try folderFrom(entry) {
                        events.append(.bookmarkFolderUpdated(folder))
                    } // TODO log this?

                case "favorites" where deleted:
                    events.append(.favoriteDeleted(id: id))

                case "favorites" where type == "favorite":
                    if let site = try siteFrom(entry) {
                        events.append(.favoriteUpdated(site))
                    } // TODO log this?

                case "favorites" where type == "folder":
                    if let folder = try folderFrom(entry) {
                        events.append(.favoriteFolderUpdated(folder))
                    } // TODO log this?

                default: break

                }
            }
        }

        try await persistence.persist(events)

        if let bookmarksLastUpdated = bookmarksLastUpdated {
            dataLastUpdated.bookmarksUpdated(bookmarksLastUpdated)
        }

        if let favoritesLastUpdated = favoritesLastUpdated {
            dataLastUpdated.favoritesUpdated(favoritesLastUpdated)
        }
    }

    func folderFrom(_ entry: [String: Any]) throws -> Folder? {
        guard let id = entry["id"] as? String,
              let encryptedTitle = entry["title"] as? String,
              let position = entry["positon"] as? Double
        else { return nil }

        let parent = entry["parent"] as? String

        let title = try crypter.base64DecodeAndDecrypt(encryptedTitle)

        return Folder(id: id, title: title, position: position, parent: parent)
    }

    func siteFrom(_ entry: [String: Any]) throws -> SavedSite? {

        guard let id = entry["id"] as? String,
              let encryptedTitle = entry["title"] as? String,
              let encryptedUrl = entry["url"] as? String,
              let position = entry["positon"] as? Double
        else { return nil }

        let parent = entry["parent"] as? String

        let title = try crypter.base64DecodeAndDecrypt(encryptedTitle)
        let url = try crypter.base64DecodeAndDecrypt(encryptedUrl)

        return SavedSite(id: id, title: title, url: url, position: position, parent: parent)
    }

}
