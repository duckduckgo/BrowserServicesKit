//
//  TaskTimeoutTests.swift
//  DuckDuckGo
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

import XCTest
@testable import Common

final class TaskTimeoutTests: XCTestCase {

    func testWithTimeoutPasses() async throws {
        struct TestError: Error {
            init() {
                fatalError("should never timeout")
            }
        }
        let result = try await withTimeout(1, throwing: TestError()) {
            try await Task.sleep(interval: 0.0001)
            return 1
        }

        XCTAssertEqual(result, 1)
    }
    
    func testWithTimeoutThrowsTimeoutError() async {
        do {
            try await withTimeout(0.0001) {
                for await _ in AsyncStream<Never>.never {}
                throw CancellationError()
            }

            XCTFail("should timeout")
        } catch {
        }
    }

}
