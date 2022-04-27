
import Foundation

extension Bundle {

    struct Keys {
        static let name = kCFBundleNameKey as String
        static let identifier = kCFBundleIdentifierKey as String
        static let buildNumber = kCFBundleVersionKey as String
        static let versionNumber = "CFBundleShortVersionString"
        static let displayName = "CFBundleDisplayName"
    }

    var displayName: String? {
        object(forInfoDictionaryKey: Keys.displayName) as? String ??
            object(forInfoDictionaryKey: Keys.name) as? String
    }

}
