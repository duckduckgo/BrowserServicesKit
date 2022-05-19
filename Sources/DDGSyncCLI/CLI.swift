
import Foundation
import DDGSync

@main
struct CLI {

    enum CLIError: Error {
        case general(_ message: String)
        case args(_ message: String)
    }

    static func main() async throws {
        print("ddgsynccli")
        print()

        guard CommandLine.arguments.count > 1 else {
            Self.usage()
            exit(1)
        }

        let baseURLString = CommandLine.arguments[1]
        let command = Array(CommandLine.arguments.dropFirst(2))

        let cli = CLI(baseURL: URL(string: baseURLString)!)

        do {
            switch command[0] {
            case "create-account":
                try checkArgs(command, min: 1)
                try await cli.createAccount(Array(command.dropFirst()))

            case "add-bookmark":
                try checkArgs(command, min: 2)
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
        } catch {
            switch error {
            case CLIError.general(let message):
                print(message)

            case CLIError.args(let message):
                print(message)
                print()
                cli.help()

            default:
                throw error
            }
        }
    }

    static func checkArgs(_ args: [String], min: Int) throws {
        guard args.count >= min else {
            throw CLIError.args("Minimum of \(min) args were expected")
        }
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
        print()

        print("Command: add-bookmark \"title\" \"valid url\" [parent id]")
        print("\tAdd a bookmark with title and url and optional parent id")
        print()

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
        let errorMessage = "\n\nusage: add-bookmark title url [parent folder id]"

        guard args.count >= 2 else {
            throw CLIError.general("Not enough args \(args)" + errorMessage)
        }

        let title = args[0]
        guard let url = URL(string: args[1]) else {
            throw CLIError.general("URL was not valid" + errorMessage)
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
        dumpBookmarks(persistence.root.children ?? [], indent: "")
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
        guard !args.isEmpty else {
            throw CLIError.general("create account requires a device name")
        }

        let deviceId = UUID().uuidString
        print("creating account for device id: ", deviceId)
        try await sync.createAccount(device: DeviceDetails(id: UUID(), name: args[0]))
        assert(sync.isAuthenticated)
    }

    private func dumpBookmarks(_ bookmarks: [Persistence.Bookmark], indent: String) {
        print(indent, bookmarks.count, " bookmarks:")
        bookmarks.sorted { $0.position < $1.position }
            .forEach {
                print(indent, "   ", $0.id, ":", $0.title)
                if let folder = $0.children {
                    dumpBookmarks(folder, indent: indent + "\t")
                } else {
                    print(indent, "   ", "url:", $0.url ?? "<url missing>")
                    print()
                }
            }
    }

}

class Persistence: LocalDataPersisting {

    class Bookmark: Codable {

        var id: String
        var title: String
        var url: String?
        var position: Double
        var children: [Bookmark]?

        init(id: String, title: String, position: Double) {
            self.id = id
            self.title = title
            self.position = position
        }

        func addBookmark(title: String, url: String) -> Bookmark {
            let position = (children?.sorted { $0.position < $1.position }.last?.position ?? 0) + 1.0
            let bookmark = Bookmark(id: UUID().uuidString, title: title, position: position)
            bookmark.url = url
            children?.append(bookmark)
            return bookmark
        }

        func addSite(_ site: SavedSite) {
            let bookmark = Bookmark(id: site.id, title: site.title, position: site.position)
            bookmark.url = site.url
            children?.append(bookmark)
        }

        func updateWithSite(_ site: SavedSite) {
            guard self.id == site.id else { fatalError("Updating wrong bookmark!") }
            self.title = site.title
            self.url = site.url
            self.position = site.position
        }

    }

    static var bookmarkFile: URL {
        return URL(fileURLWithPath: "bookmarks.json")
    }

    var root: Bookmark

    init() {
        root = (try? JSONDecoder().decode(Bookmark.self, from: Data(contentsOf: Self.bookmarkFile))) ?? Self.makeRoot()
    }

    func persist(_ events: [SyncEvent]) async throws {
         events.forEach {
            switch $0 {
            case .bookmarkUpdated(let site):
                updateBookmark(site)

            default:
                print("Unsupported sync event")
                break
            }
        }

    }

    func updateBookmark(_ site: SavedSite) {
        if let bookmark = findBookmarkWithId(site.id, root.children ?? []) {
            bookmark.updateWithSite(site)
        } else if let parent = site.parent {
            let folder = findFolderWithId(parent, root.children ?? [])
            folder.addSite(site)
        } else {
            root.addSite(site)
        }
        saveBookmarks()
    }

    func addBookmark(title: String, url: URL, parent: String?) -> SavedSite {
        let targetFolder = findFolderWithId(parent, root.children ?? [])
        let bookmark = targetFolder.addBookmark(title: title, url: url.absoluteString)
        saveBookmarks()
        return SavedSite(id: bookmark.id,
                         title: bookmark.title,
                         url: bookmark.url!,
                         position: bookmark.position,
                         parent: targetFolder.id.isEmpty ? nil : targetFolder.id)
    }

    func resetBookmarks() {
        root = Self.makeRoot()
        saveBookmarks()
    }

    func saveBookmarks() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(root).write(to: Self.bookmarkFile)
    }

    private func findFolderWithId(_ id: String?, _ children: [Bookmark]) -> Bookmark {
        guard let id = id else { return root }
        for bookmark in children {
            if bookmark.id == id {
                return bookmark
            } else if let children = bookmark.children {
                return findFolderWithId(id, children)
            }
        }
        return root
    }

    private func findBookmarkWithId(_ id: String, _ children: [Bookmark]) -> Bookmark? {
        for bookmark in children {
            if bookmark.id == id {
                return bookmark
            } else if let children = bookmark.children {
                return findBookmarkWithId(id, children)
            }
        }
        return nil
    }

    static func makeRoot() -> Bookmark {
        let bookmark = Bookmark(id: "", title: "", position: 0)
        bookmark.children = []
        return bookmark
    }

}
