
import Foundation
import DDGSync

print("ddgsync")

let sync = DDGSync()

Task {

    try await sync.createAccount()

    try await sync.sender().persistBookmark(SyncableBookmark(
        id: UUID(),
        version: 1,
        type: .bookmark(url: URL(string: "https://example.com")!),
        title: "Title",
        position: 1,
        parent: nil
    )).send()

    let cancellable = sync.bookmarksPublisher().sink { bookmarkEvent in
        print(bookmarkEvent)
    }

    // TODO always send zero for "latest version" so that the publisher gets called
    try await sync.fetch()

    cancellable.cancel()
}
