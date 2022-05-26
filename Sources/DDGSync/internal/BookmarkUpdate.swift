
import Foundation

struct BookmarkUpdate: Codable {
    
    let id: String?
    
    let title: String?

    let page: Page?
    let folder: Folder?
    let favorite: Favorite?

    let parent: String?
    let next: String?
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
