
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

        guard CommandLine.arguments.count > 2 else {
            Self.usage()
            exit(1)
        }

        let baseUrlString = CommandLine.arguments[1]
        let command = Array(CommandLine.arguments.dropFirst(2))

        let cli = CLI(baseUrl: URL(string: baseUrlString)!)

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
                
            case "login":
                try await cli.login(Array(command.dropFirst()))

            default:
                print("unknown command \(command[0])")
                print()
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

    init(baseUrl: URL, persistence: Persistence = Persistence()) {
        self.persistence = persistence
        self.sync = DDGSync(persistence: persistence, baseUrl: baseUrl)
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

        let savedSite = persistence.addBookmark(title: title, url: url, isFavorite: false, nextItem: nil, parent: parent)
        try await sync
            .sender()
            .persistingBookmark(savedSite)
            .send()
    }

    func viewBookmarks() {
        dumpBookmarks(persistence.root, indent: "")
    }

    func fetchAll() async throws {
        try await sync.fetchEverything()
    }

    func fetchMissing() async throws {
        try await sync.fetchLatest()
    }

    func login(_ args: [String]) async throws {
        guard args.count >= 2 else {
            throw CLIError.general("usage: login path/to/existing/client \"Device Name\"")
        }

        let path = args[0]
        let deviceName = args[1]
        let key = try loadRecoveryKey(path)

        try await sync.login(recoveryKey: key, deviceName: deviceName)
        assert(sync.isAuthenticated)
    }

    func createAccount(_ args: [String]) async throws {
        guard !args.isEmpty else {
            throw CLIError.general("create-account requires a device name")
        }

        let deviceName = args[0]

        print("creating new account")
        try await sync.createAccount(deviceName: deviceName)
        assert(sync.isAuthenticated)
    }

    private func dumpBookmarks(_ bookmarks: [Persistence.Bookmark], indent: String) {
        print(indent, bookmarks.count, " bookmarks:")
        bookmarks
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

    private func loadRecoveryKey(_ path: String) throws -> Data {
        let url = URL(fileURLWithPath: path).appendingPathComponent("account.json")
        let account = try JSONDecoder().decode(SyncAccount.self, from: Data(contentsOf: url))

        guard let userId = account.userId.data(using: .utf8) else {
            throw CLIError.general("Failed to encode userId read from account")
        }

        return account.primaryKey + userId
    }

}

class Persistence: LocalDataPersisting {

    struct Device: Encodable {
        
        let id: String
        let name: String
        
    }
    
    struct Meta: Codable {
        
        var bookmarksLastModified: String?
        
    }
    
    class Bookmark: Codable {

        var id: String
        var title: String
        var url: String?
        var isFavorite: Bool
        var children: [Bookmark]?

        init(id: String, title: String, isFavorite: Bool) {
            self.id = id
            self.title = title
            self.isFavorite = isFavorite
        }

        func updateWithSite(_ site: SavedSiteItem) {
            guard self.id == site.id else { fatalError("Updating wrong bookmark!") }
            self.title = site.title
            self.url = site.url
            self.isFavorite = site.isFavorite
        }

        func nextItemIdForBookmark(_ child: Bookmark) -> String? {
            guard let children = children,
                  let index = children.firstIndex(where: { $0.id == child.id }),
                  let sibling = children[safe: index + 1] else {
                return nil
            }
            return sibling.id
        }
    }

    static var bookmarkFile: URL {
        return URL(fileURLWithPath: "bookmarks.json")
    }

    static var metaFile: URL {
        return URL(fileURLWithPath: "meta.json")
    }

    static var devicesFile: URL {
        return URL(fileURLWithPath: "devices.json")
    }

    var bookmarksLastModified: String? {
        meta.bookmarksLastModified
    }
    
    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    } ()
    
    var root = [Bookmark]()
    var meta: Meta
    
    init() {
        root = (try? JSONDecoder().decode([Bookmark].self, from: Data(contentsOf: Self.bookmarkFile))) ?? []
        meta = (try? JSONDecoder().decode(Meta.self, from: Data(contentsOf: Self.metaFile))) ?? Meta()
    }

    func persistEvents(_ events: [SyncEvent]) async throws {
         events.forEach {
            switch $0 {
            case .bookmarkUpdated(let site):
                updateBookmark(site)

            default:
                print("Unsupported sync event")
                
            }
        }

    }
    
    func persistDevices(_ devices: [RegisteredDevice]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(devices.map { Device(id: $0.id, name: $0.name) }).write(to: Self.devicesFile)
    }
    
    func updateBookmarksLastModified(_ lastModified: String?) {
        meta.bookmarksLastModified = lastModified
        saveMeta()
    }

    func updateBookmark(_ site: SavedSiteItem) {
        if let bookmark = findBookmarkWithId(site.id, root) {
            bookmark.updateWithSite(site)
        } else if let parent = site.parent, let folder = findFolderWithId(parent, root) {
            folder.children?.append(bookmarkFromSite(site))
        } else {
            root.append(bookmarkFromSite(site))
        }
        saveBookmarks()
    }
    
    func bookmarkFromSite(_ site: SavedSiteItem) -> Bookmark {
        let bookmark = Bookmark(id: site.id, title: site.title, isFavorite: site.isFavorite)
        bookmark.url = site.url
        return bookmark
    }
    
    func addBookmark(title: String, url: URL, isFavorite: Bool, nextItem: String?, parent: String?) -> SavedSiteItem {
        let bookmark = Bookmark(id: UUID().uuidString, title: title, isFavorite: isFavorite)
        bookmark.url = url.absoluteString
    
        // TODO insert using nextItem
        if let targetFolder = findFolderWithId(parent, root) {
            targetFolder.children?.append(bookmark)
        } else {
            root.append(bookmark)
        }
        
        saveBookmarks()
        
        return SavedSiteItem(id: bookmark.id,
                         title: bookmark.title,
                         url: bookmark.url!,
                         isFavorite: isFavorite,
                         nextFavorite: nil,
                         nextItem: nextItem,
                         parent: parent)
    }

    func resetBookmarks() {
        root = []
        saveBookmarks()
    }

    func saveBookmarks() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(root).write(to: Self.bookmarkFile)
    }

    func saveMeta() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(meta).write(to: Self.metaFile)
    }

    private func nextItemIdForBookmark(_ bookmark: Bookmark, inFolder folder: [Bookmark]) -> String? {
        return nil
    }
    
    private func findFolderWithId(_ id: String?, _ children: [Bookmark]) -> Bookmark? {
        guard let id = id else { return nil }
        for bookmark in children {
            if bookmark.id == id {
                return bookmark
            } else if let children = bookmark.children {
                return findFolderWithId(id, children)
            }
        }
        return nil
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
        let bookmark = Bookmark(id: "", title: "", isFavorite: false)
        bookmark.children = []
        return bookmark
    }

}

extension Collection {

    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
