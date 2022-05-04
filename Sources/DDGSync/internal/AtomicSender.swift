
import Foundation

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

    private var bookmarks = [[String: Any]]()
    private var favorites = [[String: Any]]()

    mutating func persistBookmark(_ bookmark: SavedSite) {
        bookmarks.append(toDictionary(bookmark, asType: .bookmark))
    }

    mutating func persistBookmarkFolder(_ folder: Folder) {
        bookmarks.append(toDictionary(folder, asType: .folder))
    }

    mutating func deleteBookmark(_ bookmark: SavedSite) {
        bookmarks.append(toDictionary(bookmark, asType: .bookmark, deleted: true))
    }

    mutating func deleteBookmarkFolder(_ folder: Folder) {
        bookmarks.append(toDictionary(folder, asType: .folder, deleted: true))
    }

    mutating func persistFavorite(_ favorite: SavedSite) {
        favorites.append(toDictionary(favorite, asType: .favorite))
    }

    mutating func persistFavoriteFolder(_ folder: Folder) {
        favorites.append(toDictionary(folder, asType: .folder))
    }

    mutating func deleteFavorite(_ favorite: SavedSite) {
        favorites.append(toDictionary(favorite, asType: .favorite, deleted: true))
    }

    mutating func deleteFavoriteFolder(_ folder: Folder) {
        favorites.append(toDictionary(folder, asType: .favorite, deleted: true))
    }

    func send() async throws {

        func updates(named name: String, updates: [[String: Any]], lastUpdated: String?) -> [String: Any] {
            guard !updates.isEmpty else { return [:] }
            var result: [String: Any] = [ "updates": updates ]
            if let lastUpdated = lastUpdated {
                result["since"] = lastUpdated
            }
            return result
        }

        var bookmarksLastUpdated: String?
        var favoritesLastUpdated: String?

        var patchPayload:[String: Any] = [:]
        patchPayload.merge(updates(named: "bookmarks",
                                   updates: bookmarks,
                                   lastUpdated: bookmarksLastUpdated), uniquingKeysWith: noDictionaryOverwrites)

        patchPayload.merge(updates(named: "favorites",
                                   updates: bookmarks,
                                   lastUpdated: favoritesLastUpdated), uniquingKeysWith: noDictionaryOverwrites)

        let jsonData = try JSONSerialization.data(withJSONObject: patchPayload, options: [])
        print(String(data: jsonData, encoding: .utf8)!)

        // TODO call the server

        // TODO if server call fails, save it for later

        // TODO publish the updates

        // TODO save the version

        throw SyncError.notImplemented
    }

    // https://stackoverflow.com/a/54671872/73479
    private func toDictionary(_ thing: Any, asType type: DataType, deleted: Bool = false) -> [String: Any] {
        let mirror = Mirror(reflecting: thing)

        var dict = Dictionary(uniqueKeysWithValues: mirror.children.lazy.map { (label: String?, value: Any) -> (String, Any)? in
            guard let label = label else { return nil }
            return (label, value)
        }.compactMap { $0 })

        dict.merge(type.toDict(), uniquingKeysWith: noDictionaryOverwrites)

        if deleted {
            dict["deleted"] = 1
        }

        return dict
    }

    private func noDictionaryOverwrites(current: Any, new: Any) -> Any {
        assert(current as? String == nil) // Existing entries should not be being replaced.
        return new
    }

}

public struct SavedSite {

    public let id: String

    public let title: String
    public let url: String
    public let position: Double

    public let parent: String?

    public init(id: String, title: String, url: String, position: Double, parent: String?) {
        self.id = id
        self.title = title
        self.url = url
        self.position = position
        self.parent = parent
    }

}

public struct Folder {

    public let id: String

    public let title: String
    public let position: Double

    public let parent: String?

    public init(id: String, title: String,position: Double, parent: String?) {
        self.id = id
        self.title = title
        self.position = position
        self.parent = parent
    }

}
