
import Foundation

public protocol LocalDataPersisting {

    func persist(_ events: [SyncEvent]) async throws

}
