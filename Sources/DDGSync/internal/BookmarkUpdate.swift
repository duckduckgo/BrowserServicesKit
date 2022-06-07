
import Foundation

struct BookmarkUpdate: Codable {
    
    let id: String?
    let next: String?
    let parent: String?
    let title: String?

    let page: Page?
    let favorite: Favorite?
    let folder: Folder?

    let deleted: String?
    
    struct Page: Codable {
        
        let url: String?

    }
    
    struct Favorite: Codable {
        
        let next: String?
        
    }
    
    struct Folder: Codable {
    }

}
