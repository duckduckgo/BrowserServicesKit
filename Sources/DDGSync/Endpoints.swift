
import Foundation

public struct Endpoints {

    let signup: URL
    let login: URL

    /// Optionally has the data type(s) appended to it, e.g. `sync/bookmarks`, `sync/type1,type2,type3`
    let syncGet: URL
    
    let syncPatch: URL
    
    init(baseUrl: URL) {
        signup = baseUrl.appendingPathComponent("sync/signup")
        login = baseUrl.appendingPathComponent("sync/login")
        syncGet = baseUrl.appendingPathComponent("sync")
        syncPatch = baseUrl.appendingPathComponent("sync/data")
    }
    
}
