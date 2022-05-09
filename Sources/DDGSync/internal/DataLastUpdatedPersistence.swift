
import Foundation

struct DataLastUpdatedPersistence: DataLastUpdatedPersisting {

    var bookmarks: String? {
        return nil
    }

    var favorites: String? {
        return nil
    }

    func bookmarksUpdated(_ lastUpdated: String) {
    }

    func favoritesUpdated(_ lastUpdated: String) {
    }

}
