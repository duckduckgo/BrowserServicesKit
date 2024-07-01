//
//  AuthEndpointServiceTests.swift
//
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

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCreateAccountSuccess() async throws {
        let token = "someToken"
        let externalID = "id?"
        let status = "noidea"
        let mockedCreateAccountResponse = CreateAccountResponse(authToken: token, externalID: externalID, status: status)
        let apiService = APIServiceMock(mockAuthHeaders: ["Authorization": "Bearer " + token],
                                        mockAPICallSuccessResult: mockedCreateAccountResponse)
        let service = DefaultAuthEndpointService(currentServiceEnvironment: .staging,
                                                 apiService: apiService)
        let result = await service.createAccount(emailAccessToken: token)
        switch result {
        case .success(let success):
            XCTAssertEqual(success.authToken, token)
            XCTAssertEqual(success.externalID, externalID)
            XCTAssertEqual(success.status, status)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testCreateAccountFailure() async throws {
        let token = "someToken"
        let apiService = APIServiceMock(mockAuthHeaders: ["Authorization": "Bearer " + token],
                                        mockAPICallError: .encodingError)
        let service = DefaultAuthEndpointService(currentServiceEnvironment: .staging,
                                                 apiService: apiService)
        let result = await service.createAccount(emailAccessToken: token)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let failure):
            switch failure {
            case APIServiceError.encodingError: break
            default:
                XCTFail("Wrong error")
            }
        }
    }
}
