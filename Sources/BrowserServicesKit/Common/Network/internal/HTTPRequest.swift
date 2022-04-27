
import Foundation
import Combine

struct HTTPRequest: HTTPRequesting {

    var defaultHeaders: [String: String] {
        let acceptEncoding = "gzip;q=1.0, compress;q=0.5"
        let languages = Locale.preferredLanguages.prefix(6)
        let acceptLanguage = languages.enumerated().map { index, language in
            let q = 1.0 - (Double(index) * 0.1)
            return "\(language);q=\(q)"
        }.joined(separator: ", ")

        return [
            HTTPHeaderName.acceptEncoding: acceptEncoding,
            HTTPHeaderName.acceptLanguage: acceptLanguage,
            HTTPHeaderName.userAgent: userAgent
        ]
    }

    private var userAgent: String {
#if os(macOS)
        let ddg = "mac"
        let platform = "macOS"
#elseif os(iOS)
        let ddg = "ios"
        let platform = "iOS"
#endif
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return "ddg_\(ddg)/\(appVersion.versionNumber) (\(appVersion.identifier); \(platform) \(osVersion))"
    }

    let appVersion: AppVersion = AppVersion()
    let url: URL
    let method: HTTPRequestMethod

    private var queryItems: [URLQueryItem]?

    init(url: URL, method: HTTPRequestMethod) {
        self.url = url
        self.method = method
    }

    mutating public func addParameter(_ name: String, value: String) {
        if queryItems == nil {
            queryItems = [URLQueryItem]()
        }
        queryItems?.append(URLQueryItem(name: name, value: value))
    }

    public func execute() async throws -> HTTPResult {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url(relativeTo: nil) else {
            throw HTTPRequestError.failedToCreateRequestUrl
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        defaultHeaders.forEach { header in
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        // When we can use iOS 15 and macOS 12 only we can just use the async/await APIs for URL requests.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPResult, Error>) in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let httpResponse = response as? HTTPURLResponse {
                    continuation.resume(returning: HTTPResult(data: data, response: httpResponse))
                } else {
                    continuation.resume(throwing: HTTPRequestError.notHTTPURLResponse(response))
                }
            }.resume()
        }
    }

}
