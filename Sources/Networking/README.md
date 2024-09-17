#  Networking

This is the preferred Networking library for iOS and macOS DuckDuckGo apps.
If the library doesn't have the features you require, please improve it. 

## v2

### Usage

#### Configuration:
```
let request = APIRequestV2(url: HTTPURLResponse.testUrl,
                           method: .post,
                           queryItems: ["Query,Item1%Name": "Query,Item1%Value"],
                           headers: APIRequestV2.HeadersV2(userAgent: "UserAgent"),
                           body: Data(),
                           timeoutInterval: TimeInterval(20),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                           responseConstraints: [.allowHTTPNotModified,
                                                 .requireETagHeader,
                                                 .requireUserAgent],
                           allowedQueryReservedCharacters: CharacterSet(charactersIn: ","))!
let apiService = DefaultAPIService(urlSession: URLSession.shared)
```

#### Fetching Methods

The library provides two primary functions for fetching requests:

1. **Raw Response Fetching**: This function returns an `APIResponse`, which is a tuple containing the raw data and the HTTP response.
   
   ```swift
   let result = try await apiService.fetch(request: request)
   ```
   
   The `APIResponse` is defined as:
   
   ```swift
   typealias APIResponse = (data: Data?, httpResponse: HTTPURLResponse)
   ```

2. **Decoded Response Fetching**: This function decodes the response into an optional `String` or any object conforming to the `Decodable` protocol.
   
   ```swift
   let result: String? = try await apiService.fetch(request: request)
   let result: MyModel? = try await apiService.fetch(request: request)
   ```

**Concurrency Considerations**: This library is designed to be agnostic with respect to concurrency models. It maintains a stateless architecture, and the URLSession instance is injected by the user, thereby delegating all concurrency management decisions to the user. The library facilitates task cancellation by frequently invoking `try Task.checkCancellation()`, ensuring responsive and cooperative cancellation handling.

### Mock

The `MockPIService` implementing `APIService` can be found in `BSK/TestUtils`

```
let apiResponse = (Data(), HTTPURLResponse(url: HTTPURLResponse.testUrl,
                                    statusCode: 200,
                                    httpVersion: nil,
                                    headerFields: nil)!)
let mockedAPIService = MockAPIService(decodableResponse: Result.failure(SomeError.testError),
                              apiResponse: Result.success(apiResponse) )
```

## v1 (Legacy)

Not to be used. All V1 public functions have been deprecated and maintained only for backward compatibility. 
