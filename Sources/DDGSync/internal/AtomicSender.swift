
import Foundation
import BrowserServicesKit

struct AtomicSender: AtomicSending {

    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies

    private(set) var bookmarks = [BookmarkUpdate]()

    func persistingBookmark(_ bookmark: SavedSiteItem) throws -> AtomicSending {
        return try appendBookmark(bookmark, deleted: false)
    }

    func persistingBookmarkFolder(_ folder: SavedSiteFolder) throws -> AtomicSending {
        return try appendFolder(folder, deleted: false)
    }

    func deletingBookmark(_ bookmark: SavedSiteItem) throws -> AtomicSending {
        return try appendBookmark(bookmark, deleted: true)
    }

    func deletingBookmarkFolder(_ folder: SavedSiteFolder) throws -> AtomicSending {
        return try appendFolder(folder, deleted: true)
    }

    private func appendBookmark(_ bookmark: SavedSiteItem, deleted: Bool) throws -> AtomicSending {
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
        return AtomicSender(persistence: persistence, dependencies: dependencies, bookmarks: bookmarks + [update])
    }
    
    private func appendFolder(_ folder: SavedSiteFolder, deleted: Bool) throws -> AtomicSending {
        let encryptedTitle = try dependencies.crypter.encryptAndBase64Encode(folder.title)
        let update = BookmarkUpdate(id: folder.id,
                                    title: encryptedTitle,
                                    page: nil,
                                    folder: .init(),
                                    favorite: nil,
                                    parent: folder.parent,
                                    next: folder.nextItem,
                                    deleted: deleted ? "" : nil)
        return AtomicSender(persistence: persistence, dependencies: dependencies, bookmarks: bookmarks + [update])
    }

    func send() async throws {
        guard !bookmarks.isEmpty else { return }
        guard let token = try dependencies.secureStore.account()?.token else { throw SyncError.noToken }
        
        let updates = Updates(bookmarks: BookmarkUpdates(modified_since: persistence.bookmarksLastModified, updates: bookmarks))
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(updates)
        print(String(data: jsonData, encoding: .utf8)!)

        switch try await send(jsonData, withAuthorization: token) {
        case .success(let updates):
            if !updates.isEmpty {
                try await dependencies.responseHandler.handleUpdates(updates)
            }
            break

        case .failure(let error):
            switch error {
            case SyncError.unexpectedStatusCode(let statusCode):
                if statusCode == 403 {
                    try dependencies.secureStore.removeAccount()
                }
                
            default: break
            }
            throw error
        }
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

    struct Updates: Encodable {

        var bookmarks: BookmarkUpdates
        
    }
    
    struct BookmarkUpdates: Encodable {
        
        var modified_since: String?
        var updates: [BookmarkUpdate]
        
    }
    
}
