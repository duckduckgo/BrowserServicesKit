
import Foundation

struct AtomicSender: AtomicSending {

    private var bookmarks = [[String: Any]]()
    private var favorites = [[String: Any]]()

    mutating func persistBookmark(_ bookmark: SavedSite) {
        bookmarks.append(toDictionary(bookmark, with: ["type": "bookmark"]))
    }

    mutating func persistBookmarkFolder(_ folder: Folder) {
        bookmarks.append(toDictionary(folder, with: ["type": "folder"]))
    }

    mutating func deleteBookmark(_ bookmark: SavedSite) {
        bookmarks.append(toDictionary(bookmark, with: ["type": "bookmark"], deleted: true))
    }

    mutating func deleteBookmarkFolder(_ folder: Folder) {
        bookmarks.append(toDictionary(folder, with: ["type": "folder"], deleted: true))
    }

    mutating func persistFavorite(_ favorite: SavedSite) {
        favorites.append(toDictionary(favorite, with: ["type": "favorite"]))
    }

    mutating func persistFavoriteFolder(_ folder: Folder) {
        favorites.append(toDictionary(folder, with: ["type": "folder"]))
    }

    mutating func deleteFavorite(_ favorite: SavedSite) {
        favorites.append(toDictionary(favorite, with: ["type": "favorite"], deleted: true))
    }

    mutating func deleteFavoriteFolder(_ folder: Folder) {
        favorites.append(toDictionary(folder, with: ["type": "folder"], deleted: true))
    }

    func send() async throws {
        let mostRecentVersion = 0

        var patchPayload:[String: Any] = [:]

        patchPayload["most_recent_version"] = mostRecentVersion

        if !bookmarks.isEmpty {
            patchPayload["bookmarks"] = bookmarks
        }

        if !favorites.isEmpty {
            patchPayload["favorites"] = favorites
        }

        let jsonData = try JSONSerialization.data(withJSONObject: patchPayload, options: [])
        print(String(data: jsonData, encoding: .utf8)!)

        throw SyncError.notImplemented
    }


    private func toDictionary(_ thing: Any, with attributes: [String: Any], deleted: Bool = false) -> [String: Any] {
        // https://stackoverflow.com/a/54671872/73479
        let mirror = Mirror(reflecting: thing)

        var dict = Dictionary(uniqueKeysWithValues: mirror.children.lazy.map { (label: String?, value: Any) -> (String, Any)? in
            guard let label = label else { return nil }
            return (label, value)
        }.compactMap { $0 })

        attributes.forEach {
            dict[$0.key] = $0.value
        }

        if deleted {
            dict["deleted"] = 1
        }

        return dict
    }

}

public struct SavedSite {

    public let id: String
    public let version: Int

    public let title: String
    public let url: String
    public let position: Double

    public let parent: String?

    public init(id: String, version: Int, title: String, url: String, position: Double, parent: String?) {
        self.id = id
        self.version = version
        self.title = title
        self.url = url
        self.position = position
        self.parent = parent
    }

}

public struct Folder {

    public let id: String
    public let version: Int

    public let title: String
    public let position: Double

    public let parent: String?

    public init(id: String, version: Int, title: String,position: Double, parent: String?) {
        self.id = id
        self.version = version
        self.title = title
        self.position = position
        self.parent = parent
    }

}
