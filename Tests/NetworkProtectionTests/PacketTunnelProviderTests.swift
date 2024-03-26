//
//  PacketTunnelProviderTests.swift
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
@testable import NetworkProtection

final class PacketTunnelProviderTests: XCTestCase {

    typealias TunnelError = PacketTunnelProvider.TunnelError

    /// Tests that `TunnelError`implements `CustomNSError`.
    ///
    func testThatTunnelErrorImplementsCustomNSError() {
        let genericError: Error = TunnelError.startingTunnelWithoutAuthToken

        XCTAssertNotNil(genericError as? CustomNSError)
    }

    /// Tests that `TunnelError` has the expected underlying error information.
    ///
    func testThatTunnelErrorHasTheExpectedUnderlyingErrorInformation() {
        XCTAssertEqual(TunnelError.startingTunnelWithoutAuthToken.errorUserInfo[NSUnderlyingErrorKey] as? NSError, nil)
        XCTAssertEqual(TunnelError.simulateTunnelFailureError.errorUserInfo[NSUnderlyingErrorKey] as? NSError, nil)
        XCTAssertEqual(TunnelError.vpnAccessRevoked.errorUserInfo[NSUnderlyingErrorKey] as? NSError, nil)

        let underlyingError = NSError(domain: "test", code: 1)
        XCTAssertEqual(TunnelError.couldNotGenerateTunnelConfiguration(internalError: underlyingError).errorUserInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)
    }
}
