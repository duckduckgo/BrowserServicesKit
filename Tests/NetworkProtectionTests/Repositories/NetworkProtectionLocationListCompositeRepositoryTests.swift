//
//  NetworkProtectionLocationListCompositeRepositoryTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import NetworkProtection
@testable import NetworkProtectionTestUtils

class NetworkProtectionLocationListCompositeRepositoryTests: XCTestCase {
    var repository: NetworkProtectionLocationListCompositeRepository!
    var client: MockNetworkProtectionClient!
    var tokenStore: MockNetworkProtectionTokenStorage!

    override func setUp() {
        super.setUp()
        client = MockNetworkProtectionClient()
        tokenStore = MockNetworkProtectionTokenStorage()
        repository = NetworkProtectionLocationListCompositeRepository(client: client, tokenStore: tokenStore)
    }

    @MainActor
    override func tearDown() {
        NetworkProtectionLocationListCompositeRepository.clearCache()
        client = nil
        tokenStore = nil
        repository = nil
        super.tearDown()
    }

    func testFetchLocationList_firstCall_fetchesAndReturnsList() async throws {
        let expectedToken = "aToken"
        let expectedList: [NetworkProtectionLocation] = [
            .testData(country: "US", cities: [
                .testData(name: "New York"),
                .testData(name: "Los Angeles")
            ])
        ]
        client.stubGetLocations = .success(expectedList)
        tokenStore.stubFetchToken = expectedToken
        let locations = try await repository.fetchLocationList()
        XCTAssertEqual(expectedToken, client.spyGetLocationsAuthToken)
        XCTAssertEqual(expectedList, locations)
    }

    func testFetchLocationList_secondCall_returnsCachedList() async throws {
        let expectedToken = "aToken"
        let expectedList: [NetworkProtectionLocation] = [
            .testData(country: "DE", cities: [
                .testData(name: "Berlin")
            ])
        ]
        client.stubGetLocations = .success(expectedList)
        tokenStore.stubFetchToken = expectedToken
        _ = try await repository.fetchLocationList()
        client.spyGetLocationsAuthToken = nil
        let locations = try await repository.fetchLocationList()

        XCTAssertEqual(expectedList, locations)
        XCTAssertFalse(client.getLocationsCalled)
    }

    func testFetchLocationList_noAuthToken_throwsError() async throws {
        client.stubGetLocations = .success([.testData()])
        tokenStore.stubFetchToken = nil
        var errorResult: NetworkProtectionError?
        do {
            _ = try await repository.fetchLocationList()
        } catch let error as NetworkProtectionError {
            errorResult = error
        }

        switch errorResult {
        case .noAuthTokenFound:
            break
        default:
            XCTFail("Expected noAuthTokenFound error")
        }
    }

    func testFetchLocationList_fetchThrows_throwsError() async throws {
        client.stubGetLocations = .failure(.failedToFetchLocationList(nil))
        var errorResult: Error?
        do {
            _ = try await repository.fetchLocationList()
        } catch let error as NetworkProtectionError {
            errorResult = error
        }

        XCTAssertNotNil(errorResult)
    }
}

private extension NetworkProtectionLocation {
    static func testData(country: String = "", cities: [City] = []) -> NetworkProtectionLocation {
        return Self(country: country, cities: cities)
    }
}

private extension NetworkProtectionLocation.City {
    static func testData(name: String = "") -> NetworkProtectionLocation.City {
        Self(name: name)
    }
}
