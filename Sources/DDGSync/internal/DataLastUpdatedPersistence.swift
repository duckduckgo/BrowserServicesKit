
import Foundation

// TODO change to struct writing data
class DataLastUpdatedPersistence: DataLastUpdatedPersisting {

    var bookmarks: String?
    var favorites: String?

    func bookmarksUpdated(_ lastUpdated: String) {
        bookmarks = lastUpdated
    }

    func favoritesUpdated(_ lastUpdated: String) {
        favorites = lastUpdated
    }

    func reset() {
        bookmarks = nil
        favorites = nil
    }

}
