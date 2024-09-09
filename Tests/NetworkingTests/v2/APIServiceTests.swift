//
//  APIServiceTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
@testable import Networking
import TestUtils

final class APIServiceTests: XCTestCase {

    private var mockURLSession: URLSession {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: testConfiguration)
    }

    func testRealCallJSON() async throws { // TODO: Disable
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl,
                                                         method: .get)
        guard let request = APIRequestV2(configuration: configuration) else {
            XCTFail("Invalid API Request")
            return
        }
        let apiService = DefaultAPIService()
        let result = try await apiService.fetch(request: request)

        XCTAssertNotNil(result.data)
        XCTAssertNotNil(result.httpResponse)

        let responseHTML = String(data: result.data!, encoding: .utf8)
        XCTAssertNotNil(responseHTML)
    }

    func testRealCallString() async throws { // TODO: Disable
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl,
                                                         method: .get)
        let request = APIRequestV2(configuration: configuration)!
        let apiService = DefaultAPIService()
        let result: String = try await apiService.fetch(request: request)

        XCTAssertNotNil(result)
    }

    func testQueryItems() async throws {
        let qItems = [URLQueryItem(name: "qName1", value: "qValue1"),
                      URLQueryItem(name: "qName2", value: "qValue2")]
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl,
                                                         method: .get,
                                                         queryParameters: qItems)
        MockURLProtocol.requestHandler = { request in
            let urlComponents = URLComponents(string: request.url!.absoluteString)!
            XCTAssertTrue(urlComponents.queryItems!.contains(qItems))
            return (HTTPURLResponse.ok, nil)
        }
        let request = APIRequestV2(configuration: configuration)!
        let apiService = DefaultAPIService(urlSession: mockURLSession)
        let result = try await apiService.fetch(request: request)
    }

    func testURLRequestError() async throws {
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl, method: .get)
        let request = APIRequestV2(configuration: configuration)!

        enum TestError: Error {
            case anError
        }

        MockURLProtocol.requestHandler = { request in throw TestError.anError }

        let apiService = DefaultAPIService(urlSession: mockURLSession)

        do {
            _ = try await apiService.fetch(request: request)
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequestV2.Error,
                  case .urlSession = error else {
                XCTFail("Unexpected error thrown: \(error.localizedDescription).")
                return
            }
        }
    }

    // MARK: - allowHTTPNotModified

    func testResponseRequirementAllowHTTPNotModifiedSuccess() async throws {
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl, method: .get)
        let requirements = [APIResponseRequirementV2.allowHTTPNotModified ]
        let request = APIRequestV2(configuration: configuration, requirements: requirements)!

        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.notModified, Data()) }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        let result = try await apiService.fetch(request: request)
        XCTAssertNotNil(result)
        XCTAssertEqual(result.httpResponse.statusCode, HTTPStatusCode.notModified.rawValue)
    }

    func testResponseRequirementAllowHTTPNotModifiedFailure() async throws {
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl, method: .get)
        let request = APIRequestV2(configuration: configuration)!

        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.notModified, Data()) }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        do {
            _ = try await apiService.fetch(request: request)
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequestV2.Error,
                  case .unsatisfiedRequirement(let requirement) = error,
                  requirement == APIResponseRequirementV2.allowHTTPNotModified
            else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    // MARK: - requireETagHeader

    func testResponseRequirementRequireETagHeaderSuccess() async throws {
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl, method: .get)
        let requirements: [APIResponseRequirementV2] = [
            APIResponseRequirementV2.requireETagHeader
        ]
        let request = APIRequestV2(configuration: configuration, requirements: requirements)!
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, nil) } // HTTPURLResponse.ok contains etag

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        let result = try await apiService.fetch(request: request)
        XCTAssertNotNil(result)
        XCTAssertEqual(result.httpResponse.statusCode, HTTPStatusCode.ok.rawValue)
    }

    func testResponseRequirementRequireETagHeaderFailure() async throws {
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl, method: .get)
        let requirements = [ APIResponseRequirementV2.requireETagHeader ]
        let request = APIRequestV2(configuration: configuration, requirements: requirements)!

        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.okNoEtag, nil) }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        do {
            _ = try await apiService.fetch(request: request)
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequestV2.Error,
                  case .unsatisfiedRequirement(let requirement) = error,
                  requirement == APIResponseRequirementV2.requireETagHeader
            else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    // MARK: - requireUserAgent

    func testResponseRequirementRequireUserAgentSuccess() async throws {
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl, method: .get)
        let requirements = [ APIResponseRequirementV2.requireUserAgent ]
        let request = APIRequestV2(configuration: configuration, requirements: requirements)!

        MockURLProtocol.requestHandler = { _ in
            ( HTTPURLResponse.okUserAgent, nil)
        }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        let result: APIService.APIResponse = try await apiService.fetch(request: request)
        XCTAssertNotNil(result)
        XCTAssertEqual(result.httpResponse.statusCode, HTTPStatusCode.ok.rawValue)
    }

    func testResponseRequirementRequireUserAgentFailure() async throws {
        let configuration = APIRequestV2.ConfigurationV2(url: HTTPURLResponse.testUrl, method: .get)
        let requirements = [ APIResponseRequirementV2.requireUserAgent ]
        let request = APIRequestV2(configuration: configuration, requirements: requirements)!

        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, nil) }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        do {
            _ = try await apiService.fetch(request: request)
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequestV2.Error,
                  case .unsatisfiedRequirement(let requirement) = error,
                  requirement == APIResponseRequirementV2.requireUserAgent
            else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }


}
