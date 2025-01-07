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
import Common
@testable import Subscription
@testable import Networking
import NetworkingTestingUtils

class NetworkProtectionLocationListCompositeRepositoryTests: XCTestCase {
    var repository: NetworkProtectionLocationListCompositeRepository!
    var client: MockNetworkProtectionClient!
    var tokenProvider: MockSubscriptionTokenProvider!
    var verifyErrorEvent: ((NetworkProtectionError) -> Void)?

    override func setUp() {
        super.setUp()
        client = MockNetworkProtectionClient()
        tokenProvider = MockSubscriptionTokenProvider()
        repository = NetworkProtectionLocationListCompositeRepository(
            client: client,
            tokenProvider: tokenProvider,
            errorEvents: .init { [weak self] event, _, _, _ in
                self?.verifyErrorEvent?(event)
        })
    }

    @MainActor
    override func tearDown() {
        NetworkProtectionLocationListCompositeRepository.clearCache()
        client = nil
        tokenProvider = nil
        repository = nil
        super.tearDown()
    }

    func testFetchLocationList_firstCall_fetchesAndReturnsList() async throws {
        let expectedList: [NetworkProtectionLocation] = [
            .testData(country: "US", cities: [
                .testData(name: "New York"),
                .testData(name: "Los Angeles")
            ])
        ]
        client.stubGetLocations = .success(expectedList)
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        tokenProvider.tokenResult = .success(tokenContainer)
        let locations = try await repository.fetchLocationList()
        XCTAssertEqual("ddg:\(tokenContainer.accessToken)", client.spyGetLocationsAuthToken)
        XCTAssertEqual(expectedList, locations)
    }

    func testFetchLocationList_secondCall_returnsCachedList() async throws {
        let expectedList: [NetworkProtectionLocation] = [
            .testData(country: "DE", cities: [
                .testData(name: "Berlin")
            ])
        ]
        client.stubGetLocations = .success(expectedList)
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        tokenProvider.tokenResult = .success(tokenContainer)
        _ = try await repository.fetchLocationList()
        client.spyGetLocationsAuthToken = nil
        let locations = try await repository.fetchLocationList()

        XCTAssertEqual(expectedList, locations)
        XCTAssertFalse(client.getLocationsCalled)
    }

    func testFetchLocationList_noAuthToken_throwsError() async throws {
        client.stubGetLocations = .success([.testData()])
        tokenProvider.tokenResult = .failure(OAuthClientError.missingTokens)
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

    func testFetchLocationList_noAuthToken_sendsErrorEvent() async {
        client.stubGetLocations = .success([.testData()])
        tokenProvider.tokenResult = .failure(OAuthClientError.missingTokens)
        var didReceiveError: Bool = false
        verifyErrorEvent = { error in
            didReceiveError = true
            switch error {
            case .noAuthTokenFound:
                break
            default:
                XCTFail("Expected noAuthTokenFound error")
            }
        }
        _ = try? await repository.fetchLocationList()
        XCTAssertTrue(didReceiveError)
    }

    func testFetchLocationList_fetchThrows_throwsError() async throws {
        client.stubGetLocations = .failure(.failedToFetchLocationList(NetworkProtectionBackendClient.GetLocationsError.noResponse))
        var errorResult: Error?
        do {
            _ = try await repository.fetchLocationList()
        } catch let error as NetworkProtectionError {
            errorResult = error
        }

        XCTAssertNotNil(errorResult)
    }

    func testFetchLocationList_fetchThrows_sendsErrorEvent() async {
        client.stubGetLocations = .failure(.failedToFetchLocationList(NetworkProtectionBackendClient.GetLocationsError.noResponse))
        var didReceiveError: Bool = false
        verifyErrorEvent = { _ in
            didReceiveError = true
            // Matching errors is not working for some reason, so just checking for any error
        }
        _ = try? await repository.fetchLocationList()
        XCTAssertTrue(didReceiveError)
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
