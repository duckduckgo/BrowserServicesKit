
import Foundation

// TODO change to struct writing data
class DataLastUpdatedPersistence: DataLastUpdatedPersisting {

    var bookmarks: String?

    func bookmarksUpdated(_ lastUpdated: String) {
        bookmarks = lastUpdated
    }

    func reset() {
        bookmarks = nil
    }

}
