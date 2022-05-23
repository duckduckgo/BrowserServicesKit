
import Foundation
import BrowserServicesKit

struct AtomicSender: AtomicSending {

    enum DataType {

        case bookmark
        case folder

        func toDict() -> [String: String] {
            switch self {
            case .bookmark: return ["type": "bookmark"]
            case .folder: return ["type": "folder"]
            }
        }

    }

    let dependencies: SyncDependencies
    let syncUrl: URL
    let token: String

    private(set) var bookmarks = [[String: Any]]()

    func persistingBookmark(_ bookmark: SavedSite) -> AtomicSending {
        return appendingBookmark(toTypedDictionary(bookmark, asType: .bookmark))
    }

    func persistingBookmarkFolder(_ folder: Folder) -> AtomicSending {
        return appendingBookmark(toTypedDictionary(folder, asType: .folder))
    }

    func deletingBookmark(_ bookmark: SavedSite) -> AtomicSending {
        return appendingBookmark(toTypedDictionary(bookmark, asType: .bookmark, deleted: true))
    }

    func deletingBookmarkFolder(_ folder: Folder) -> AtomicSending {
        return appendingBookmark(toTypedDictionary(folder, asType: .folder, deleted: true))
    }

    func send() async throws {

        func updates(_ updates: [[String: Any]], since: String?) -> [String: Any] {
            var dict = [String: Any]()
            dict["modified_since"] = since
            dict["updates"] = updates
            return dict
        }

        let bookmarks = try self.bookmarks.map { try encrypt($0) }

        let bookmarksLastUpdated = dependencies.dataLastUpdated.bookmarks

        // TODO load existing payload saved while offline, and update it
        var payload = [String: Any]()

        if !bookmarks.isEmpty {
            payload["bookmarks"] = updates(bookmarks, since: bookmarksLastUpdated)
        }

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        print(String(data: jsonData, encoding: .utf8)!)

        switch try await send(jsonData) {
        case .success(let updates):
            try await dependencies.responseHandler.handleUpdates(updates)
            break

        case .failure(let error):
            // TODO save for later
            print(error)
            break
        }
    }

    private func send(_ json: Data) async throws -> Result<[String: Any], Error> {
        var request = dependencies.api.createRequest(url: syncUrl, method: .PATCH)
        request.addHeader("Authorization", value: "bearer \(token)")
        request.setBody(body: json, withContentType: "application/json")
        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let data = result.data else {
            return .success([:])
        }

        guard let updates = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.unableToDecodeResponse("Failed to convert response to JSON dictionary of type [String: Any]")
        }

        return .success(updates)
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

    private func encrypt(_ dict: [String: Any]) throws -> [String: Any] {
        var encrypted = dict
        try dict.forEach { key, value in
            if ["title", "url"].contains(key), let value = value as? String {
                let encryptedValue = try dependencies.crypter.encryptAndBase64Encode(value)
                encrypted[key] = encryptedValue
            }
        }
        return encrypted
    }

    private func appendingBookmark(_ bookmark: [String: Any]) -> AtomicSending {
        return AtomicSender(dependencies: dependencies,
                            syncUrl: syncUrl,
                            token: token,
                            bookmarks: bookmarks + [bookmark])
    }

}
