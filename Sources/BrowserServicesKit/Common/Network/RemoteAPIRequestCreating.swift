
import Foundation

public protocol RemoteAPIRequestCreating {

    func createRequest(url: URL, method: RequestMethod) -> HTTPRequesting

}

public struct RemoteAPIRequestCreator: RemoteAPIRequestCreating {

    public init() { }

    public func createRequest(url: URL, method: RequestMethod) -> HTTPRequesting {
        return HTTPRequest(url: url, method: method)
    }

}

public enum RequestMethod: String {

    case GET
    case POST

}

public protocol HTTPRequesting {

    mutating func addParameter(_ name: String, value: String)

    func execute() async throws -> HTTPURLResponse

}

