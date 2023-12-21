//
//  NetworkProtectionLatencyMonitorTests.swift
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
import Combine
@testable import NetworkProtection

final class NetworkProtectionLatencyMonitorTests: XCTestCase {
    private var monitor: NetworkProtectionLatencyMonitor?
    private var cancellable: AnyCancellable?

    override func setUp() async throws {
        try await super.setUp()

        monitor = NetworkProtectionLatencyMonitor(serverIP: { nil }, timerQueue: DispatchQueue.main, log: .networkProtectionPixel)

        try await monitor?.start()
    }

    override func tearDown() async throws {
        await monitor?.stop()
    }

    func testInvalidIP() async {
        let expectation = XCTestExpectation(description: "Invalid IP reported")
        cancellable = monitor?.publisher
            .sink { result in
                switch result {
                case .error:
                    expectation.fulfill()
                case .quality:
                    break
                }
            }
        await monitor?.measureLatency()
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testPingFailure() async {
        let expectation = XCTestExpectation(description: "Ping failure reported")
        cancellable = monitor?.publisher
            .sink { result in
                switch result {
                case .error:
                    expectation.fulfill()
                case .quality:
                    break
                }
            }
        monitor?.simulateLatency(-1)
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testConnectionQuality() async {
        await testConnectionLatency(0.0, expecting: .excellent)
        await testConnectionLatency(0.1, expecting: .excellent)
        await testConnectionLatency(20.0, expecting: .good)
        await testConnectionLatency(21.0, expecting: .good)
        await testConnectionLatency(50.0, expecting: .moderate)
        await testConnectionLatency(51.0, expecting: .moderate)
        await testConnectionLatency(200.0, expecting: .poor)
        await testConnectionLatency(201.0, expecting: .poor)
        await testConnectionLatency(300.0, expecting: .terrible)
        await testConnectionLatency(301.0, expecting: .terrible)
    }

    private func testConnectionLatency(_ timeInterval: TimeInterval, expecting expectedQuality: NetworkProtectionLatencyMonitor.ConnectionQuality) async {
        let monitor = NetworkProtectionLatencyMonitor(serverIP: { nil }, timerQueue: DispatchQueue.main, log: .networkProtectionPixel)

        var reportedQuality = NetworkProtectionLatencyMonitor.ConnectionQuality.unknown
        cancellable = monitor.publisher
            .sink { result in
                switch result {
                case .quality(let quality):
                    reportedQuality = quality
                case .error:
                    XCTFail("Unexpected result")
                }
            }

        try? await monitor.start()
        monitor.simulateLatency(timeInterval)
        await monitor.stop()

        XCTAssertEqual(expectedQuality, reportedQuality)
    }
}
