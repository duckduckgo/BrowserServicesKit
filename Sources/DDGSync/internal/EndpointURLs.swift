
import Foundation

public struct EndpointURLs {

    let signup: URL

    init(baseURL: URL) {
        signup = baseURL.appendingPathComponent("sync-auth/signup")
    }

}
