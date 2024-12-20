//
//  MaliciousSiteProtectionAPIClientTests.swift
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
import Foundation
import Networking
import TestUtils
import XCTest

@testable import MaliciousSiteProtection

final class MaliciousSiteProtectionAPIClientTests: XCTestCase {

    var mockService: MockAPIService!
    var client: MaliciousSiteProtection.APIClient!

    override func setUp() {
        super.setUp()
        mockService = MockAPIService()
        client = .init(environment: MaliciousSiteDetector.APIEnvironment.staging, service: mockService)
    }

    override func tearDown() {
        mockService = nil
        client = nil
        super.tearDown()
    }

    func testWhenPhishingFilterSetRequestedAndSucceeds_ChangeSetIsReturned() async throws {
        // Given
        let insertFilter = Filter(hash: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947", regex: ".")
        let deleteFilter = Filter(hash: "6a929cd0b3ba4677eaedf1b2bdaf3ff89281cca94f688c83103bc9a676aea46d", regex: "(?i)^https?\\:\\/\\/[\\w\\-\\.]+(?:\\:(?:80|443))?")
        let expectedResponse = APIClient.Response.FiltersChangeSet(insert: [insertFilter], delete: [deleteFilter], revision: 666, replace: false)
        mockService.requestHandler = { [unowned self] in
            XCTAssertEqual($0.urlRequest.url, client.environment.url(for: .filterSet(.init(threatKind: .phishing, revision: 666))))
            let data = try? JSONEncoder().encode(expectedResponse)
            let response = HTTPURLResponse(url: $0.urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return .success(.init(data: data, httpResponse: response))
        }

        // When
        let response = try await client.filtersChangeSet(for: .phishing, revision: 666)

        // Then
        XCTAssertEqual(response, expectedResponse)
    }

    func testWhenHashPrefixesRequestedAndSucceeds_ChangeSetIsReturned() async throws {
        // Given
        let expectedResponse = APIClient.Response.HashPrefixesChangeSet(insert: ["abc"], delete: ["def"], revision: 1, replace: false)
        mockService.requestHandler = { [unowned self] in
            XCTAssertEqual($0.urlRequest.url, client.environment.url(for: .hashPrefixSet(.init(threatKind: .phishing, revision: 1))))
            let data = try? JSONEncoder().encode(expectedResponse)
            let response = HTTPURLResponse(url: $0.urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return .success(.init(data: data, httpResponse: response))
        }

        // When
        let response = try await client.hashPrefixesChangeSet(for: .phishing, revision: 1)

        // Then
        XCTAssertEqual(response, expectedResponse)
    }

    func testWhenMatchesRequestedAndSucceeds_MatchesAreReturned() async throws {
        // Given
        let expectedResponse = APIClient.Response.Matches(matches: [Match(hostname: "example.com", url: "https://example.com/test", regex: ".", hash: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947", category: nil)])
        mockService.requestHandler = { [unowned self] in
            XCTAssertEqual($0.urlRequest.url, client.environment.url(for: .matches(.init(hashPrefix: "abc"))))
            let data = try? JSONEncoder().encode(expectedResponse)
            let response = HTTPURLResponse(url: $0.urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return .success(.init(data: data, httpResponse: response))
        }

        // When
        let response = try await client.matches(forHashPrefix: "abc")

        // Then
        XCTAssertEqual(response.matches, expectedResponse.matches)
    }

    func testWhenHashPrefixesRequestFails_ErrorThrown() async throws {
        // Given
        let invalidRevision = -1
        mockService.requestHandler = {
            // Simulate a failure or invalid request
            let response = HTTPURLResponse(url: $0.urlRequest.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return .success(.init(data: nil, httpResponse: response))
        }

        do {
        let response = try await client.hashPrefixesChangeSet(for: .phishing, revision: invalidRevision)
            XCTFail("Unexpected \(response) expected throw")
        } catch {
        }
    }

    func testWhenFilterSetRequestFails_ErrorThrown() async throws {
        // Given
        let invalidRevision = -1
        mockService.requestHandler = {
            // Simulate a failure or invalid request
            let response = HTTPURLResponse(url: $0.urlRequest.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return .success(.init(data: nil, httpResponse: response))
        }

        do {
        let response = try await client.hashPrefixesChangeSet(for: .phishing, revision: invalidRevision)
            XCTFail("Unexpected \(response) expected throw")
        } catch {
        }
    }

    func testWhenMatchesRequestFails_ErrorThrown() async throws {
        // Given
        let invalidHashPrefix = ""
        mockService.requestHandler = {
            // Simulate a failure or invalid request
            let response = HTTPURLResponse(url: $0.urlRequest.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return .success(.init(data: nil, httpResponse: response))
        }

        do {
            let response = try await client.matches(forHashPrefix: invalidHashPrefix)
            XCTFail("Unexpected \(response) expected throw")
        } catch {
        }
    }

}
