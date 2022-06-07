
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
        print(FileManager.default.currentDirectoryPath)
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
    let secureStore: SecureStoring
    var sync: DDGSyncing

    init(baseUrl: URL) {
        self.persistence = Persistence()
        self.secureStore = SecureStore()
        self.sync = DDGSync(persistence: persistence,
                            fileStorageUrl: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                            baseUrl: baseUrl,
                            secureStore: secureStore)
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
        persistence.printBookmarks()
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

    var bookmarksLastModified: String?
    var events = Events.load()
    
    func updateBookmarksLastModified(_ lastModified: String?) {
        bookmarksLastModified = lastModified
    }
    
    func persistDevices(_ devices: [RegisteredDevice]) async throws {
        JSONEncoder.write(devices, toFile: "devices.json")
    }
    
    func persistEvents(_ events: [SyncEvent]) async throws {
        
        events.forEach { event in
            switch event {
            case .bookmarkDeleted(let id):
                self.events.items[id] = nil
                
            case .bookmarkFolderUpdated(let folder):
                self.events.folders[folder.id] = folder
                
            case .bookmarkUpdated(let item):
                self.events.items[item.id] = item
            }
        }
        
        self.events.save()
    }
    
    func addBookmark(title: String, url: URL, isFavorite: Bool, nextItem: String?, parent: String?) -> SavedSiteItem {
        let savedItem = SavedSiteItem(id: UUID().uuidString, title: title, url: url.absoluteString, isFavorite: isFavorite, nextFavorite: nil, nextItem: nextItem, parent: parent)
        
        events.items[savedItem.id] = savedItem
        events.save()
        
        return savedItem
    }
    
    func printBookmarks(parent: String? = nil, indent: String = "") {
        print("items", events.items)
        print("folders", events.folders)
    }
    
    func resetBookmarks() {
        events.folders = [:]
        events.items = [:]
    }
    
    class Events: Codable {
        
        var items = [String: SavedSiteItem]()
        var folders = [String: SavedSiteFolder]()
        
        static let file = "events.json"
          
        static func load() -> Events {
            JSONDecoder.read(type: Self.self, fromFile: Self.file) ?? Events()
        }
        
        func save() {
            JSONEncoder.write(self, toFile: Self.file)
        }
        
    }
}

struct SecureStore: SecureStoring {
    
    static let file = "account.json"
    
    func persistAccount(_ account: SyncAccount) throws {
        JSONEncoder.write(account, toFile: Self.file)
    }
    
    func account() throws -> SyncAccount? {
        return JSONDecoder.read(type: SyncAccount.self, fromFile: Self.file)
    }
    
    func removeAccount() throws {
        try FileManager.default.removeItem(atPath: Self.file)
    }

}

extension Collection {

    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension JSONEncoder {
    
    static func write<T: Codable>(_ codable: T, toFile file: String) {
        try! JSONEncoder().encode(codable).write(to: URL(fileURLWithPath: file))
    }
    
}

extension JSONDecoder {

    static func read<T: Codable>(type: T.Type, fromFile file: String) -> T? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else { return nil }
        return try! JSONDecoder().decode(type.self, from: data)
    }

}
