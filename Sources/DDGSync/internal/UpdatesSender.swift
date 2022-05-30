
import Foundation
import BrowserServicesKit

struct UpdatesSender: UpdatesSending {

    static let offlineUpdatesFile: URL = {
        FileManager.default.applicationSupportDirectoryForComponent(named: "Sync")
            .appendingPathComponent("offline-updates.json")
    }()
    
    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies

    private(set) var bookmarks = [BookmarkUpdate]()

    func persistingBookmark(_ bookmark: SavedSiteItem) throws -> UpdatesSending {
        return try appendBookmark(bookmark, deleted: false)
    }

    func persistingBookmarkFolder(_ folder: SavedSiteFolder) throws -> UpdatesSending {
        return try appendFolder(folder, deleted: false)
    }

    func deletingBookmark(_ bookmark: SavedSiteItem) throws -> UpdatesSending {
        return try appendBookmark(bookmark, deleted: true)
    }

    func deletingBookmarkFolder(_ folder: SavedSiteFolder) throws -> UpdatesSending {
        return try appendFolder(folder, deleted: true)
    }

    private func appendBookmark(_ bookmark: SavedSiteItem, deleted: Bool) throws -> UpdatesSender {
        let encryptedTitle = try dependencies.crypter.encryptAndBase64Encode(bookmark.title)
        let encryptedUrl = try dependencies.crypter.encryptAndBase64Encode(bookmark.url)
        let update = BookmarkUpdate(id: bookmark.id,
                                    title: encryptedTitle,
                                    page: .init(url: encryptedUrl),
                                    folder: nil,
                                    favorite: bookmark.isFavorite ? .init(next: bookmark.nextFavorite) : nil,
                                    parent: bookmark.parent,
                                    next: bookmark.nextItem,
                                    deleted: deleted ? "" : nil)
        return UpdatesSender(persistence: persistence, dependencies: dependencies, bookmarks: bookmarks + [update])
    }
    
    private func appendFolder(_ folder: SavedSiteFolder, deleted: Bool) throws -> UpdatesSender {
        let encryptedTitle = try dependencies.crypter.encryptAndBase64Encode(folder.title)
        let update = BookmarkUpdate(id: folder.id,
                                    title: encryptedTitle,
                                    page: nil,
                                    folder: .init(),
                                    favorite: nil,
                                    parent: folder.parent,
                                    next: folder.nextItem,
                                    deleted: deleted ? "" : nil)
        return UpdatesSender(persistence: persistence, dependencies: dependencies, bookmarks: bookmarks + [update])
    }

    func send() async throws {
        guard let account = try dependencies.secureStore.account() else { throw SyncError.accountNotFound }
        guard let token = account.token else { throw SyncError.noToken }
 
        let updates = prepareUpdates()
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(updates)

        switch try await send(jsonData, withAuthorization: token) {
        case .success(let updates):
            if !updates.isEmpty {
                do {
                    try await dependencies.responseHandler.handleUpdates(updates)
                } catch {
                    throw error
                }
            }
            try removeOfflineFile()

        case .failure(let error):
            switch error {
            case SyncError.unexpectedStatusCode(let statusCode):
                if statusCode == 403 {
                    try dependencies.secureStore.removeAccount()
                    try removeOfflineFile()
                    throw SyncError.accountRemoved
                }
                
            default: break
            }
            
            // Save updates for later unless this was a 403
            try saveForLater(updates)
        }
    }
    
    private func prepareUpdates() -> Updates {
        if var updates = loadPreviouslyFailedUpdates() {
            updates.bookmarks.modified_since = persistence.bookmarksLastModified
            updates.bookmarks.updates += self.bookmarks
            return updates
        }
        return Updates(bookmarks: BookmarkUpdates(modified_since: persistence.bookmarksLastModified, updates: bookmarks))
    }
  
    private func loadPreviouslyFailedUpdates() -> Updates? {
        guard let data = try? Data(contentsOf: Self.offlineUpdatesFile) else { return nil }
        return try? JSONDecoder().decode(Updates.self, from: data)
    }
    
    private func saveForLater(_ updates: Updates) throws {
        try JSONEncoder().encode(updates).write(to: Self.offlineUpdatesFile, options: .atomic)
    }
    
    private func removeOfflineFile() throws {
        try FileManager.default.removeItem(at: Self.offlineUpdatesFile)
    }
    
    private func send(_ json: Data, withAuthorization authorization: String) async throws -> Result<Data, Error> {
        guard let syncUrl = try dependencies.secureStore.account()?.baseDataUrl.appendingPathComponent(Endpoints.sync) else { throw SyncError.accountNotFound }
        
        var request = dependencies.api.createRequest(url: syncUrl, method: .PATCH)
        request.addHeader("Authorization", value: "bearer \(authorization)")
        request.setBody(body: json, withContentType: "application/json")
        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let data = result.data else {
            throw SyncError.noResponseBody
        }

        return .success(data)
    }

    struct Updates: Codable {

        var bookmarks: BookmarkUpdates
        
    }
    
    struct BookmarkUpdates: Codable {
        
        var modified_since: String?
        var updates: [BookmarkUpdate]
        
    }
    
}
