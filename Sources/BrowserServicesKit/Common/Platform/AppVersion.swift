import Foundation

public struct AppVersion {

    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public var name: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Keys.name) as? String ?? ""
    }

    public var identifier: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Keys.identifier) as? String ?? ""
    }

    public var majorVersionNumber: String {
        return String(versionNumber.split(separator: ".").first ?? "")
    }

    public var versionNumber: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Keys.versionNumber) as? String ?? ""
    }
    
    public var versionAndBuildNumber: String {
        return "\(versionNumber).\(buildNumber)"
    }

    public var buildNumber: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Keys.buildNumber) as? String ?? ""
    }

}
