#  Networking

This is the preferred Networking library for iOS and macOS DuckDuckGo apps.
If the library doesn't have the features you require, please improve it. 

## v2

### USage

API request configuration:
```
let request = APIRequestV2(url: HTTPURLResponse.testUrl,
                           method: .post,
                           queryItems: ["Query,Item1%Name": "Query,Item1%Value"],
                           headers: APIRequestV2.HeadersV2(userAgent: "UserAgent"),
                           body: Data(),
                           timeoutInterval: TimeInterval(20),
                           cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                           requirements: [APIResponseRequirementV2.allowHTTPNotModified,
                                          APIResponseRequirementV2.requireETagHeader,
                                          APIResponseRequirementV2.requireUserAgent],
                           allowedQueryReservedCharacters: CharacterSet(charactersIn: ","))!
let apiService = DefaultAPIService(urlSession: URLSession.shared)
```

The request can be fetched using two functions:

One returning a `APIResponse`, aka `(data: Data?, httpResponse: HTTPURLResponse)`

`let result = try await apiService.fetch(request: request)`

And one decoding an optional `String` or any object implementing `Decodable`

`let result: String? = try await apiService.fetch(request: request)`

`let result: MyModel? = try await apiService.fetch(request: request)`

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

Not to be used, maintained only for backward compatibility 
