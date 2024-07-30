//
//  AuthEndpointServiceTests.swift
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
@testable import Subscription
import SubscriptionTestingUtilities

final class AuthEndpointServiceTests: XCTestCase {

    private struct Constants {
        static let authToken = "this-is-auth-token"
        static let accessToken = "this-is-access-token"
        static let externalID = "0084026b-0340-4880-0000-0006026abd00"
        static let email = "glhffz9e@duck.com"
        static let authorizationHeader = ["Authorization": "Bearer TOKEN"]

        static let invalidTokenError = APIServiceError.serverError(statusCode: 401, error: "invalid_token")
    }

    func testGetAccessTokenCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        let onExecute: (APIServiceMock.ExecuteAPICallParameters) -> Void = { parameters in
            let (method, endpoint, headers, _) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "access-token")
            XCTAssertEqual(headers, Constants.authorizationHeader)
        }

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, onExecuteAPICall: onExecute)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        _ = await authService.getAccessToken(token: Constants.authToken)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetAccessTokenSuccess() async throws {
        let json = """
        {
            "accessToken": "\(Constants.accessToken)",
        }
        """.data(using: .utf8)!

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockResponseJSONData: json)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await authService.getAccessToken(token: Constants.authToken)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.accessToken, Constants.accessToken)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetAccessTokenError() async throws {
        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockAPICallError: Constants.invalidTokenError)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await authService.getAccessToken(token: Constants.authToken)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    func testValidateTokenCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        let onExecute: (APIServiceMock.ExecuteAPICallParameters) -> Void = { parameters in
            let (method, endpoint, headers, _) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "validate-token")
            XCTAssertEqual(headers, Constants.authorizationHeader)
        }

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, onExecuteAPICall: onExecute)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        _ = await authService.validateToken(accessToken: Constants.accessToken)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testValidateTokenSuccess() async throws {
        let json = """
        {
            "account": {
                "id": 149718,
                "external_id": "\(Constants.externalID)",
                "email": "\(Constants.email)",
                "entitlements": [
                    {"id":24, "name":"subscriber", "product":"Network Protection"},
                    {"id":25, "name":"subscriber", "product":"Data Broker Protection"},
                    {"id":26, "name":"subscriber", "product":"Identity Theft Restoration"}
                ]
            }
        }
        """.data(using: .utf8)!

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockResponseJSONData: json)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await authService.validateToken(accessToken: Constants.accessToken)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.account.externalID, Constants.externalID)
            XCTAssertEqual(success.account.email, Constants.email)
            XCTAssertEqual(success.account.entitlements.count, 3)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testValidateTokenError() async throws {
        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockAPICallError: Constants.invalidTokenError)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await authService.validateToken(accessToken: Constants.accessToken)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    func testCreateAccountCall() async throws {
        let apiServiceCalledExpectation = expectation(description: "apiService")

        let onExecute: (APIServiceMock.ExecuteAPICallParameters) -> Void = { parameters in
            let (method, endpoint, _, _) = parameters;

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "POST")
            XCTAssertEqual(endpoint, "account/create")
        }

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, onExecuteAPICall: onExecute)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        _ = await authService.createAccount(emailAccessToken: nil)
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testCreateAccountSuccess() async throws {
        let json = """
        {
            "auth_token": "\(Constants.authToken)",
            "external_id": "\(Constants.externalID)",
            "status": "created"
        }
        """.data(using: .utf8)!

        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockResponseJSONData: json)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await authService.createAccount(emailAccessToken: nil)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.authToken, Constants.authToken)
            XCTAssertEqual(success.externalID, Constants.externalID)
            XCTAssertEqual(success.status, "created")
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testCreateAccountError() async throws {
        let apiService = APIServiceMock(mockAuthHeaders: Constants.authorizationHeader, mockAPICallError: Constants.invalidTokenError)
        let authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)

        let result = await authService.createAccount(emailAccessToken: nil)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }
}
