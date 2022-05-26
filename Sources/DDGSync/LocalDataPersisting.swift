
import Foundation

public protocol LocalDataPersisting {

    func persistEvents(_ events: [SyncEvent]) async throws
    func persistDevices(_ devices: [RegisteredDevice]) async throws

}
