//
//  PhishingDetectionClientTests.swift
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
import XCTest
@testable import PhishingDetection

final class PhishingDetectionAPIClientTests: XCTestCase {

    var mockSession: MockURLSession!
    var client: PhishingDetectionAPIClient!

    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        client = PhishingDetectionAPIClient(environment: .staging, session: mockSession)
    }

    override func tearDown() {
        mockSession = nil
        client = nil
        super.tearDown()
    }

    func testGetFilterSetSuccess() async {
        // Given
        let insertFilter = Filter(hashValue: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947", regex: ".")
        let deleteFilter = Filter(hashValue: "6a929cd0b3ba4677eaedf1b2bdaf3ff89281cca94f688c83103bc9a676aea46d", regex: "(?i)^https?\\:\\/\\/[\\w\\-\\.]+(?:\\:(?:80|443))?")
        let expectedResponse = FilterSetResponse(insert: [insertFilter], delete: [deleteFilter], revision: 1, replace: false)
        mockSession.data = try? JSONEncoder().encode(expectedResponse)
        mockSession.response = HTTPURLResponse(url: client.filterSetURL, statusCode: 200, httpVersion: nil, headerFields: nil)

        // When
        let response = await client.getFilterSet(revision: 1)

        // Then
        XCTAssertEqual(response, expectedResponse)
    }

    func testGetHashPrefixesSuccess() async {
        // Given
        let expectedResponse = HashPrefixResponse(insert: ["abc"], delete: ["def"], revision: 1, replace: false)
        mockSession.data = try? JSONEncoder().encode(expectedResponse)
        mockSession.response = HTTPURLResponse(url: client.hashPrefixURL, statusCode: 200, httpVersion: nil, headerFields: nil)

        // When
        let response = await client.getHashPrefixes(revision: 1)

        // Then
        XCTAssertEqual(response, expectedResponse)
    }

    func testGetMatchesSuccess() async {
        // Given
        let expectedResponse = MatchResponse(matches: [Match(hostname: "example.com", url: "https://example.com/test", regex: ".", hash: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947")])
        mockSession.data = try? JSONEncoder().encode(expectedResponse)
        mockSession.response = HTTPURLResponse(url: client.matchesURL, statusCode: 200, httpVersion: nil, headerFields: nil)

        // When
        let response = await client.getMatches(hashPrefix: "abc")

        // Then
        XCTAssertEqual(response, expectedResponse.matches)
    }

    func testGetFilterSetInvalidURL() async {
        // Given
        let invalidRevision = -1

        // When
        let response = await client.getFilterSet(revision: invalidRevision)

        // Then
        XCTAssertEqual(response, FilterSetResponse(insert: [], delete: [], revision: invalidRevision, replace: false))
    }

    func testGetHashPrefixesInvalidURL() async {
        // Given
        let invalidRevision = -1

        // When
        let response = await client.getHashPrefixes(revision: invalidRevision)

        // Then
        XCTAssertEqual(response, HashPrefixResponse(insert: [], delete: [], revision: invalidRevision, replace: false))
    }

    func testGetMatchesInvalidURL() async {
        // Given
        let invalidHashPrefix = ""

        // When
        let response = await client.getMatches(hashPrefix: invalidHashPrefix)

        // Then
        XCTAssertTrue(response.isEmpty)
    }
}

class MockURLSession: URLSessionProtocol {
    var data: Data?
    var response: URLResponse?
    var error: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = error {
            throw error
        }
        return (data ?? Data(), response ?? URLResponse())
    }
}
