
import Foundation
import DDGSync

@main
struct CLI {

    enum CLIError: Error {
        case general(_ message: String)
    }

    static func main() async throws {
        print("ddgsync IN")

        guard CommandLine.arguments.count > 1 else {
            Self.usage()
            exit(1)
        }

        let baseURLString = CommandLine.arguments[1]
        let command = Array(CommandLine.arguments.dropFirst())

        let cli = CLI(baseURL: URL(string: baseURLString)!)

        switch command[0] {
        case "create-account":
            try await cli.createAccount(Array(command.dropFirst()))

        case "add-bookmark":
            try await cli.addBookmark(Array(command.dropFirst()))

        case "reset-bookmarks":
            cli.resetBookmarks()

        case "view-bookmarks":
            cli.viewBookmarks()

        case "fetch-all":
            try await cli.fetchAll()

        case "fetch-missing":
            try await cli.fetchMissing()

        default:
            cli.help()
        }

        print("ddgsync OUT")
    }

    static func usage() {
        print("usage: ddgsynccli <base url> <command> [arg1 arg2 ...]")
    }

    let persistence: Persistence
    var sync: DDGSyncing

    init(baseURL: URL, persistence: Persistence = Persistence()) {
        self.persistence = persistence
        self.sync = DDGSync(persistence: persistence, baseURL: baseURL)
    }

    func help() {
        Self.usage()
        print()

        print("Command: create-account \"device name\"")
        print("\tInitialises current directory as a client")
        print()

        print("Command: login <path to existing client> \"device name\"")
        print("\tLogs in, simulating the scanning of a primary key by reading the info from the given path")

        print("Command: view-bookmarks")
        print("\tView bookmarks stored locally")
        print()

        print("Command: reset-bookmarks")
        print("\tClears the local bookmarks only")
        print()

        print("Command: fetch-all")
        print("\tFetch all data from server and add/update/delete local data.")
        print()

        print("Command: fetch-missing")
        print("\tFetch only data updated since last time.")
        print()
    }

    func resetBookmarks() {
        persistence.resetBookmarks()
    }

    func addBookmark(_ args: [String]) async throws {
        let errorMessage = "usage: add-bookmark title url [parent folder id]"

        guard args.count < 2 else {
            throw CLIError.general(errorMessage)
        }

        let title = args[0]
        guard let url = URL(string: args[1]) else {
            throw CLIError.general(errorMessage)
        }

        var parent: String?
        if args.count > 2 {
            parent = args[2]
        }


        var sender = try sync.sender()
        let savedSite = persistence.addBookmark(title: title, url: url, parent: parent)
        sender.persistBookmark(savedSite)
        try await sender.send()
    }

    func viewBookmarks() {
        dumpBookmarks(persistence.root?.children ?? [], indent: "")
    }

    func fetchAll() async throws {
        try await sync.fetchEverything()
    }

    func fetchMissing() async throws {
        try await sync.fetchLatest()
    }

    func login(_ args: [String]) async throws {

    }

    func createAccount(_ args: [String]) async throws {

        if !sync.isAuthenticated {
            let deviceId = UUID().uuidString
            print("creating account for device id: ", deviceId)
            try await sync.createAccount(device: DeviceDetails(id: UUID(), name: "Test Device"))

            assert(sync.isAuthenticated)

            print("persisting bookmark")
            var sender = try sync.sender()
            sender.persistBookmark(SavedSite(id: UUID().uuidString, title: "Example", url: "https://example.com", position: 1.56, parent: nil))
            try await sender.send()
        }

    }

    private func dumpBookmarks(_ bookmarks: [Persistence.Bookmark], indent: String) {
        bookmarks.sorted { $0.position < $1.position }
            .forEach {
                print($0.id, ":", $0.title)
                if let folder = $0.children {
                    dumpBookmarks(folder, indent: indent + "\t")
                } else {
                    print(indent, $0.url ?? "<url missing>")
                }
            }
    }

}

class Persistence: LocalDataPersisting {

    struct Bookmark: Codable {

        var id: String
        var title: String
        var url: String?
        var position: Double
        var children: [Bookmark]?

        mutating func addBookmark(title: String, url: String) -> Bookmark {
            let position = (children?.sorted { $0.position < $1.position }.last?.position ?? 0) + 1.0
            let bookmark = Bookmark(id: UUID().uuidString, title: title, url: url, position: position)
            children?.append(bookmark)
            return bookmark
        }

    }

    var events = [SyncEvent]()

    var bookmarkFile: URL {
        return URL(fileURLWithPath: "bookmarks.json")
    }

    var root: Bookmark? {
        get {
            return try? JSONDecoder().decode(Bookmark.self, from: Data(contentsOf: bookmarkFile))
        }

        set {
            guard let root = newValue else {
                try? FileManager.default.removeItem(at: bookmarkFile)
                return
            }
            try? JSONEncoder().encode(root).write(to: bookmarkFile)
        }
    }

    init() {
        resetBookmarks()
    }

    func persist(_ events: [SyncEvent]) async throws {
        print(#function, events)
        self.events = events
    }

    func addBookmark(title: String, url: URL, parent: String?) -> SavedSite {
        var targetFolder = findFolderWithId(parent, root?.children ?? [])
        let bookmark = targetFolder.addBookmark(title: title, url: url.absoluteString)

        return SavedSite(id: bookmark.id,
                         title: bookmark.title,
                         url: bookmark.url!,
                         position: bookmark.position,
                         parent: targetFolder.id.isEmpty ? nil : targetFolder.id)
    }

    func resetBookmarks() {
        root = Bookmark(id: "", title: "", position: 0.0, children: [])
    }

    private func findFolderWithId(_ id: String?, _ children: [Bookmark]) -> Bookmark {
        guard let id = id else { return root! }
        for bookmark in children {
            if bookmark.id == id {
                return bookmark
            } else if let children = bookmark.children {
                return findFolderWithId(id, children)
            }
        }
        return root!
    }

}
