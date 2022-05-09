
import Foundation
import DDGSync

@main
struct CLI {

    static func main() async throws {
        print("ddgsync IN")

        let baseURLString = CommandLine.arguments.count == 1 ? "https://e54a-20-75-144-152.ngrok.io" : CommandLine.arguments[1]
        let sync = DDGSync(persistence: Persistence(), baseURL: URL(string: baseURLString)!)

        print("subscribe to state changes")
        let cancellable = sync.statePublisher().sink { state in
            print("State changed", state)
        }

        let deviceId = UUID().uuidString
        print("creating account for device id: ", deviceId)

        try await sync.createAccount(device: DeviceDetails(id: UUID(), name: "Test Device"))

        print("persisting bookmark")
        var sender = try sync.sender()
        sender.persistBookmark(SavedSite(id: UUID().uuidString, title: "Example", url: "https://example.com", position: 1.0, parent: nil))
        try await sender.send()

        // TODO always send zero for "latest version" so that the publisher gets called
        print("fetching bookmarks")
        try await sync.fetch()

        print("cancelling state change subscription")
        cancellable.cancel()

        print("ddgsync OUT")
    }

}

struct Persistence: LocalDataPersisting {
    func deleteBookmark(_ bookmark: SavedSite) async throws {
        print(#function, bookmark)
    }

    func deleteFavorite(_ favorite: SavedSite) async throws {
        print(#function, favorite)
    }

    func deleteBookmarksFolder(_ folder: Folder) async throws {
        print(#function, folder)
    }

    func deleteFavoritesFolder(_ folder: Folder) async throws {
        print(#function, folder)
    }

    func persistBookmark(_ bookmark: SavedSite) async throws {
        print(#function, bookmark)
    }

    func persistFavorite(_ favorite: SavedSite) async throws {
        print(#function, favorite)
    }

    func persistBookmarkFolder(_ folder: Folder) async throws {
        print(#function, folder)
    }

    func persistFavoritesFolder(_ folder: Folder) async throws {
        print(#function, folder)
    }

}
