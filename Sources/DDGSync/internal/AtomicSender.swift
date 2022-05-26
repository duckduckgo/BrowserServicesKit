
import Foundation
import BrowserServicesKit

struct AtomicSender: AtomicSending {

    let dependencies: SyncDependencies
    let syncUrl: URL
    let token: String

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
        return AtomicSender(dependencies: dependencies, syncUrl: syncUrl, token: token, bookmarks: bookmarks + [update])
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
        return AtomicSender(dependencies: dependencies, syncUrl: syncUrl, token: token, bookmarks: bookmarks + [update])
    }

    func send() async throws {
        guard !bookmarks.isEmpty else { return }
        
        let updates = Updates(bookmarks: BookmarkUpdates(modified_since: dependencies.dataLastUpdated.bookmarks, updates: bookmarks))
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(updates)
        print(String(data: jsonData, encoding: .utf8)!)

        switch try await send(jsonData) {
        case .success(let updates):
            if !updates.isEmpty {
                try await dependencies.responseHandler.handleUpdates(updates)
            }
            break

        case .failure(let error):
            // TODO save for later
            print(error)
            break
        }
    }

    private func send(_ json: Data) async throws -> Result<Data, Error> {
        var request = dependencies.api.createRequest(url: syncUrl, method: .PATCH)
        request.addHeader("Authorization", value: "bearer \(token)")
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
