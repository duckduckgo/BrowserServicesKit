
import Foundation
import DDGSync

@main
struct CLI {

    static func main() async throws {
        print("ddgsync IN")

        let baseURLString = CommandLine.arguments.count == 1 ? "https://cb74-20-75-144-152.ngrok.io" : CommandLine.arguments[1]
        let sync = DDGSync(baseURL: URL(string: baseURLString)!)

        let deviceId = UUID().uuidString
        print("creating account for device id: ", deviceId)

        try await sync.createAccount(device: DeviceDetails(id: UUID(), name: "Test Device"))

        print("persisting bookmark")
        try await sync.sender().persistBookmark(SyncableBookmark(
            id: UUID(),
            version: 1,
            type: .bookmark(url: URL(string: "https://example.com")!),
            title: "Title",
            position: 1,
            parent: nil
        )).send()

        print("subscribing to bookmarks")
        let cancellable = sync.bookmarksPublisher().sink { bookmarkEvent in
            print(bookmarkEvent)
        }

        // TODO always send zero for "latest version" so that the publisher gets called
        print("fetching bookmarks")
        try await sync.fetch()

        print("cancelling subscription")
        cancellable.cancel()

        print("ddgsync OUT")
    }

}
