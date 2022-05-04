
import Foundation
import DDGSync

@main
struct CLI {

    static func main() async throws {
        print("ddgsync IN")

        let baseURLString = CommandLine.arguments.count == 1 ? "https://ae32-20-75-144-152.ngrok.io" : CommandLine.arguments[1]
        let sync = DDGSync(baseURL: URL(string: baseURLString)!)

        let deviceId = UUID().uuidString
        print("creating account for device id: ", deviceId)

        try await sync.createAccount(device: DeviceDetails(id: UUID(), name: "Test Device"))

        print("persisting bookmark")
        var sender = try sync.sender()
        sender.persistBookmark(SavedSite(id: UUID().uuidString, version: 0, title: "Example", url: "https://example.com", position: 1.0, parent: nil))
        try await sender.send()

        print("subscribing to events")
        let cancellable = sync.eventPublisher().sink { event in
            print(event)
        }

        // TODO always send zero for "latest version" so that the publisher gets called
        print("fetching bookmarks")
        try await sync.fetch()

        print("cancelling subscription")
        cancellable.cancel()

        print("ddgsync OUT")
    }

}
