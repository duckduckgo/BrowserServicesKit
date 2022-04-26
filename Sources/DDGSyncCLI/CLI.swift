
import Foundation
import DDGSync

@main
struct CLI {

    static func main() async throws {
        print("ddgsync")

        let deviceId = UUID().uuidString
        print("creating account for device id: ", deviceId)

        let sync = DDGSync(baseURL: URL(string: CommandLine.arguments[1])!)

        try await sync.createAccount(device: DeviceDetails(id: UUID(), name: "Test Device"))

        try await sync.sender().persistBookmark(SyncableBookmark(
            id: UUID(),
            version: 1,
            type: .bookmark(url: URL(string: "https://example.com")!),
            title: "Title",
            position: 1,
            parent: nil
        )).send()

        let cancellable = sync.bookmarksPublisher().sink { bookmarkEvent in
            print(bookmarkEvent)
        }

        // TODO always send zero for "latest version" so that the publisher gets called
        try await sync.fetch()

        cancellable.cancel()
    }
}
