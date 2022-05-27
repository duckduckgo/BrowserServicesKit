
import Foundation

public protocol LocalDataPersisting {

    var bookmarksLastModified: String? { get }
    func updateBookmarksLastModified(_ lastModified: String?)
    
    func persistEvents(_ events: [SyncEvent]) async throws
    func persistDevices(_ devices: [RegisteredDevice]) async throws

}
