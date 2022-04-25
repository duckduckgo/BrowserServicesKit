import XCTest
@testable import DDGSync

class DDGSyncTests: XCTestCase {

    public func test() async throws  {

        let sync = DDGSync()

        try await sync.sender()
            .persistBookmark(SyncableBookmark(id: UUID(), version: 1, type: .folder(name: "Folder"), title: "Title", position: 1, parent: nil))
            .persistBookmark(SyncableBookmark(id: UUID(), version: 1, type: .folder(name: "Folder 2"), title: "Title 2", position: 2, parent: nil))
            .send()

    }

}
