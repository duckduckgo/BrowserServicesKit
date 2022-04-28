
import Foundation

public protocol RemoteAPIRequestCreating {

    func createRequest(url: URL, method: HTTPRequestMethod) -> HTTPRequesting

}

public struct RemoteAPIRequestCreator: RemoteAPIRequestCreating {

    public init() { }

    public func createRequest(url: URL, method: HTTPRequestMethod) -> HTTPRequesting {
        return HTTPRequest(url: url, method: method)
    }

}

public enum HTTPRequestMethod: String {

    case GET
    case POST

}

public protocol HTTPRequesting {

    mutating func addParameter(_ name: String, value: String)

    mutating func setBody(body: Data, withContentType contentType: String)

    func execute() async throws -> HTTPResult

}

enum HTTPHeaderName {
    static let acceptEncoding = "Accept-Encoding"
    static let acceptLanguage = "Accept-Language"
    static let userAgent = "User-Agent"
    static let etag = "ETag"
    static let ifNoneMatch = "If-None-Match"
    static let moreInfo = "X-DuckDuckGo-MoreInfo"
    static let contentType = "Content-Type"
}

enum HTTPRequestError: Error {
    case failedToCreateRequestUrl
    case notHTTPURLResponse(URLResponse?)
    case bodyWithoutContentType
    case contentTypeWithoutBody
}

public struct HTTPResult {

    public let data: Data?
    public let response: HTTPURLResponse

}
