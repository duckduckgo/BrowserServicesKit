
import Foundation

extension String {
    var testSchemeNormalized: String {
        self.replacingOccurrences(of: "https://", with: "test://").replacingOccurrences(of: "http://", with: "test://")
    }
}
