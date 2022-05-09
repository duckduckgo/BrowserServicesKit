
import Foundation
import BrowserServicesKit

struct AtomicSender: AtomicSending {

    enum DataType {

        case bookmark
        case favorite
        case folder

        func toDict() -> [String: String] {
            switch self {
            case .bookmark: return ["type": "bookmark"]
            case .favorite: return ["type": "favorite"]
            case .folder: return ["type": "folder"]
            }
        }

    }

    public let syncUrl: URL
    public let token: String
    public let api: RemoteAPIRequestCreating

    private var bookmarks = [[String: Any]]()
    private var favorites = [[String: Any]]()

    init(syncUrl: URL, token: String, api: RemoteAPIRequestCreating) {
        self.syncUrl = syncUrl
        self.token = token
        self.api = api
    }

    mutating func persistBookmark(_ bookmark: SavedSite) {
        bookmarks.append(toTypedDictionary(bookmark, asType: .bookmark))
    }

    mutating func persistBookmarkFolder(_ folder: Folder) {
        bookmarks.append(toTypedDictionary(folder, asType: .folder))
    }

    mutating func deleteBookmark(_ bookmark: SavedSite) {
        bookmarks.append(toTypedDictionary(bookmark, asType: .bookmark, deleted: true))
    }

    mutating func deleteBookmarkFolder(_ folder: Folder) {
        bookmarks.append(toTypedDictionary(folder, asType: .folder, deleted: true))
    }

    mutating func persistFavorite(_ favorite: SavedSite) {
        favorites.append(toTypedDictionary(favorite, asType: .favorite))
    }

    mutating func persistFavoriteFolder(_ folder: Folder) {
        favorites.append(toTypedDictionary(folder, asType: .folder))
    }

    mutating func deleteFavorite(_ favorite: SavedSite) {
        favorites.append(toTypedDictionary(favorite, asType: .favorite, deleted: true))
    }

    mutating func deleteFavoriteFolder(_ folder: Folder) {
        favorites.append(toTypedDictionary(folder, asType: .favorite, deleted: true))
    }

    func send() async throws {
        func updates(_ updates: [[String: Any]], since: String?) -> [String: Any] {
            var dict = [String: Any]()
            if let since = since {
                dict["since"] = since
            }
            dict["updates"] = updates
            return dict
        }

        var bookmarksLastUpdated: String?
        var favoritesLastUpdated: String?

        var payload = [String: Any]()

        if !bookmarks.isEmpty {
            payload["bookmarks"] = updates(bookmarks, since: bookmarksLastUpdated)
        }

        if !favorites.isEmpty {
            payload["favorites"] = updates(favorites, since: favoritesLastUpdated)
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        print(String(data: jsonData, encoding: .utf8)!)

        switch try await send(jsonData) {
        case .success(let updates):
            // TODO apply updates
            // TODO save the version
            break

        case .failure(let error):
            // TODO save for later
            break
        }

        throw SyncError.notImplemented
    }

    private func send(_ json: Data) async throws -> Result<[String], Error> {
        var request = api.createRequest(url: syncUrl, method: .PATCH)
        request.addHeader("Authorization", value: "bearer $token") // TODO $token
        request.setBody(body: json, withContentType: "application/json")
        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }
        // TODO parse the result
        return .success([])
    }

    // https://stackoverflow.com/a/54671872/73479
    private func toDictionary(_ thing: Any) -> [String: Any] {
        let mirror = Mirror(reflecting: thing)
        return Dictionary(uniqueKeysWithValues: mirror.children.lazy.map { (label: String?, value: Any) -> (String, Any)? in
            guard let label = label else { return nil }
            return (label, value)
        }.compactMap { $0 })
    }

    private func toTypedDictionary(_ thing: Any, asType type: DataType, deleted: Bool = false) -> [String: Any] {
        var dict = toDictionary(thing)
        dict.merge(type.toDict()) { (_, new ) in new }
        if deleted {
            dict["deleted"] = 1
        }
        return dict
    }

}
