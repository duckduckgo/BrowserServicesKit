
import Foundation

// TODO change to struct writing data
class DataLastModified: DataLastModifiedPersisting {

    var bookmarks: String?

    func updateBookmarks(_ lastModified: String) {
        bookmarks = lastModified
    }
    
    func reset() {
        bookmarks = nil
    }

}
