
import Foundation
import Combine

public enum BookmarkType {

    case bookmark(url: URL)
    case folder(name: String)

}

public struct SyncableBookmark: Syncable {

    public let id: UUID
    public let version: Int

    public let type: BookmarkType
    public let title: String
    public let position: Double
    public let parent: UUID?

    public init(id: UUID, version: Int, type: BookmarkType, title: String, position: Double, parent: UUID?) {
        self.id = id
        self.version = version
        self.type = type
        self.title = title
        self.position = position
        self.parent = parent
    }

}
