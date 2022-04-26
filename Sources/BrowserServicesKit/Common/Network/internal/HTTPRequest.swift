
import Foundation

struct HTTPRequest: HTTPRequesting {

    enum HTTPRequestError: Error {
        case failedToCreateRequestUrl
    }

    let url: URL
    let method: RequestMethod

    private var queryItems: [URLQueryItem]?

    init(url: URL, method: RequestMethod) {
        self.url = url
        self.method = method
    }

    mutating public func addParameter(_ name: String, value: String) {
        if queryItems == nil {
            queryItems = [URLQueryItem]()
        }
        queryItems?.append(URLQueryItem(name: name, value: value))
    }

    public func execute() async throws -> HTTPURLResponse {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw HTTPRequestError.failedToCreateRequestUrl
        }

        return HTTPURLResponse(url: url, statusCode: 412, httpVersion: nil, headerFields: nil)!
    }

}
