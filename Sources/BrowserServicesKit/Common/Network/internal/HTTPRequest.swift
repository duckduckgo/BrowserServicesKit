
import Foundation

struct HTTPRequest: HTTPRequesting {

    let url: URL
    let method: RequestMethod

    init(url: URL, method: RequestMethod) {
        self.url = url
        self.method = method
    }

    mutating public func addParameter(_ name: String, value: String) {
    }

    public func execute() async -> HTTPURLResponse {
        return HTTPURLResponse(url: url, statusCode: 412, httpVersion: nil, headerFields: nil)!
    }

}
