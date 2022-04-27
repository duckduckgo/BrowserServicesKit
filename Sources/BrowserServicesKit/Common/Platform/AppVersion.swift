import Foundation

public struct AppVersion {

    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var name: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Keys.name) as? String ?? ""
    }

    var identifier: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Keys.identifier) as? String ?? ""
    }

    var majorVersionNumber: String {
        return String(versionNumber.split(separator: ".").first ?? "")
    }

    var versionNumber: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Keys.versionNumber) as? String ?? ""
    }

    var buildNumber: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Keys.buildNumber) as? String ?? ""
    }

}
