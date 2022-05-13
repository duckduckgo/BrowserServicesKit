
import Foundation
import DDGSync

@main
struct CLI {

    static func main() async throws {
        print("ddgsync IN")

        let persistence = Persistence()

        let baseURLString = CommandLine.arguments.count == 1 ? "https://3ece-20-75-144-152.ngrok.io" : CommandLine.arguments[1]
        let sync = DDGSync(persistence: persistence, baseURL: URL(string: baseURLString)!)

        print("subscribe to state changes")
        let cancellable = sync.statePublisher().sink { state in
            print("State changed", state)
        }

        let deviceId = UUID().uuidString
        print("creating account for device id: ", deviceId)

        try await sync.createAccount(device: DeviceDetails(id: UUID(), name: "Test Device"))

        print("persisting bookmark")
        var sender = try sync.sender()
        sender.persistBookmark(SavedSite(id: UUID().uuidString, title: "Example", url: "https://example.com", position: 1.56, parent: nil))
        try await sender.send()

        print("fetching data")
        try await sync.fetchLatest()
        print("latest:", persistence.events)

        try await sync.fetchEverything()
        print("everything:", persistence.events)

        print("cancelling state change subscription")
        cancellable.cancel()

        print("ddgsync OUT")
    }

}

class Persistence: LocalDataPersisting {

    var events = [SyncEvent]()

    func persist(_ events: [SyncEvent]) async throws {
        print(#function, events)
        self.events = events
    }

}
