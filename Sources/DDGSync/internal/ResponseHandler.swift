
import Foundation

struct ResponseHandler: ResponseHandling {

    let persistence: LocalDataPersisting
    let dataLastModified: DataLastModifiedPersisting
    let crypter: Crypting

    func handleUpdates(_ data: Data) async throws {
        guard !data.isEmpty else { throw SyncError.unableToDecodeResponse("Data is empty") }
        
        let decoder = JSONDecoder()
        let deltas = try decoder.decode(SyncDelta.self, from: data)
        
        var syncEvents = [SyncEvent]()
        
        deltas.bookmarks?.entries.forEach { bookmarkUpdate in
            do {
                guard let event = try bookmarkUpdateToEvent(bookmarkUpdate) else { return }
                syncEvents.append(event)
            } catch {
                // Nothing much we can do here and we don't want to break everything because of some dodgy data, but we don't lose this info either in case something more critical is going wrong. 
                // TODO log this error
            }
        }
        
        try await persistence.persistEvents(syncEvents)

        // Only save this after things have been persisted
        if let bookmarksLastModified = deltas.bookmarks?.last_modified {
            dataLastModified.updateBookmarks(bookmarksLastModified)
        }
    }
    
    private func bookmarkUpdateToEvent(_ bookmarkUpdate: BookmarkUpdate) throws -> SyncEvent? {
        guard let id = bookmarkUpdate.id else { return nil }
        guard let encryptedTitle = bookmarkUpdate.title else { return nil }
        
        let title = try crypter.base64DecodeAndDecrypt(encryptedTitle)
        
        if bookmarkUpdate.deleted != nil {
            
            return .bookmarkDeleted(id:id)
            
        } else if bookmarkUpdate.folder != nil {
            
            return .bookmarkFolderUpdated(SavedSiteFolder(id: id,
                                         title: title,
                                         nextItem: bookmarkUpdate.next,
                                         parent: bookmarkUpdate.parent))
        } else {
            
            guard let encryptedUrl = bookmarkUpdate.page?.url else { return nil }
            let url = try crypter.base64DecodeAndDecrypt(encryptedUrl)
            let savedSite = SavedSiteItem(id: id,
                                      title: title,
                                      url: url,
                                      isFavorite: bookmarkUpdate.favorite != nil,
                                      nextFavorite: bookmarkUpdate.favorite?.next,
                                      nextItem: bookmarkUpdate.next,
                                      parent: bookmarkUpdate.parent)
            return .bookmarkUpdated(savedSite)
        }
    }
    
    struct SyncDelta: Decodable {
        
        var bookmarks: BookmarkDeltas?
        
    }
    
    struct BookmarkDeltas: Decodable {
        
        var last_modified: String?
        var entries: [BookmarkUpdate]
        
    }
        
}
