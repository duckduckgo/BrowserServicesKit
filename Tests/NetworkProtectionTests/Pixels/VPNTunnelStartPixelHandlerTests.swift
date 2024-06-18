//
//  VPNTunnelStartPixelHandlerTests.swift
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

import Common
import XCTest
import Network
@testable import NetworkProtection

final class VPNTunnelStartPixelHandlerTests: XCTestCase {

    private final class ValidationHandler {
        private let beginFired: XCTestExpectation
        private let successFired: XCTestExpectation
        private let failureFired: XCTestExpectation
        private let noOtherPixelFired: XCTestExpectation

        init(beginFired: XCTestExpectation,
             successFired: XCTestExpectation,
             failureFired: XCTestExpectation,
             noOtherPixelFired: XCTestExpectation) {

            self.beginFired = beginFired
            self.successFired = successFired
            self.failureFired = failureFired
            self.noOtherPixelFired = noOtherPixelFired
        }

        private(set) lazy var eventHandler = EventMapping<PacketTunnelProvider.Event> { [weak self] event, _, _, _ in

            guard let self else {
                return
            }

            switch event {
            case .tunnelStartAttempt(let step):
                switch step {
                case .begin:
                    self.beginFired.fulfill()
                case .success:
                    self.successFired.fulfill()
                case .failure:
                    self.failureFired.fulfill()
                }
            default:
                XCTFail("An unexpected pixel was fired")
            }
        }
    }

    func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    func makeFiredExpectation(description: String, count: Int = 1) -> XCTestExpectation {
        let expectation = expectation(description: description)
        expectation.expectedFulfillmentCount = count
        expectation.assertForOverFulfill = true
        return expectation
    }

    func makeNotFiredExpectation(description: String) -> XCTestExpectation {
        let expectation = expectation(description: description)
        expectation.isInverted = true
        return expectation
    }

    // MARK: - Simple success

    func testManualStartSuccess() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired")
        let successFiredExpectation = makeFiredExpectation(description: "Success pixel was fired")
        let failureFiredExpectation = makeNotFiredExpectation(description: "Failure pixel was not fired")
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let onDemand = false
        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)

        handler.handle(.begin, onDemand: onDemand)
        handler.handle(.success, onDemand: onDemand)

        waitForExpectations(timeout: 0.1)
    }

    func testOnDemandStartSuccess() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired")
        let successFiredExpectation = makeFiredExpectation(description: "Success pixel was fired")
        let failureFiredExpectation = makeNotFiredExpectation(description: "Failure pixel was not fired")
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let onDemand = true
        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)

        handler.handle(.begin, onDemand: onDemand)
        handler.handle(.success, onDemand: onDemand)

        waitForExpectations(timeout: 0.1)
    }

    // MARK: - Simple failure

    func testManualStartFailure() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired")
        let successFiredExpectation = makeNotFiredExpectation(description: "Success pixel was not fired")
        let failureFiredExpectation = makeFiredExpectation(description: "Failure pixel was fired")
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let onDemand = false
        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)

        handler.handle(.begin, onDemand: onDemand)
        handler.handle(.failure(NSError()), onDemand: onDemand)

        waitForExpectations(timeout: 0.1)
    }

    func testOnDemandStartFailure() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired")
        let successFiredExpectation = makeNotFiredExpectation(description: "Success pixel was not fired")
        let failureFiredExpectation = makeFiredExpectation(description: "Failure pixel was fired")
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let onDemand = true
        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)

        handler.handle(.begin, onDemand: onDemand)
        handler.handle(.failure(NSError()), onDemand: onDemand)

        waitForExpectations(timeout: 0.1)
    }

    // MARK: - Several failures in a row

    func testManualAndOnDemandFailureBothReported() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired", count: 2)
        let successFiredExpectation = makeNotFiredExpectation(description: "Success pixel was not fired")
        let failureFiredExpectation = makeFiredExpectation(description: "Failure pixel was fired", count: 2)
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)

        handler.handle(.begin, onDemand: false)
        handler.handle(.failure(NSError()), onDemand: false)
        handler.handle(.begin, onDemand: true)
        handler.handle(.failure(NSError()), onDemand: true)

        waitForExpectations(timeout: 0.1)
    }

    func testSecondOnDemandFailureSilenced() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired")
        let successFiredExpectation = makeNotFiredExpectation(description: "Success pixel was not fired")
        let failureFiredExpectation = makeFiredExpectation(description: "Failure pixel was fired")
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)

        handler.handle(.begin, onDemand: true)
        handler.handle(.failure(NSError()), onDemand: true)
        handler.handle(.begin, onDemand: true)
        handler.handle(.failure(NSError()), onDemand: true)

        waitForExpectations(timeout: 0.1)
    }

    func testSecondOnDemandFailureNotSilencedAfterReboot() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired", count: 2)
        let successFiredExpectation = makeNotFiredExpectation(description: "Success pixel was not fired")
        let failureFiredExpectation = makeFiredExpectation(description: "Failure pixel was fired", count: 2)
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)

        handler.handle(.begin, onDemand: true)
        handler.handle(.failure(NSError()), onDemand: true)

        let handlerAfterReboot = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: Date(), userDefaults: defaults)

        handlerAfterReboot.handle(.begin, onDemand: true)
        handlerAfterReboot.handle(.failure(NSError()), onDemand: true)

        waitForExpectations(timeout: 0.1)
    }

    // MARK: - Re-enabling firing

    func testManualAttemptsAlwaysFire() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired")
        let successFiredExpectation = makeNotFiredExpectation(description: "Success pixel was not fired")
        let failureFiredExpectation = makeFiredExpectation(description: "Failure pixel was fired")
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)
        handler.canFire = false

        handler.handle(.begin, onDemand: false)
        handler.handle(.failure(NSError()), onDemand: false)

        waitForExpectations(timeout: 0.1)
    }

    func testOnDemandSuccessRestoresFiring() {
        let beginFiredExpectation = makeFiredExpectation(description: "Begin pixel was fired")
        let successFiredExpectation = makeNotFiredExpectation(description: "Success pixel was not fired")
        let failureFiredExpectation = makeFiredExpectation(description: "Failure pixel was fired")
        let noOtherPixelFiredExpectation = makeNotFiredExpectation(description: "No other pixel was fired")

        let validationHandler = ValidationHandler(beginFired: beginFiredExpectation, successFired: successFiredExpectation, failureFired: failureFiredExpectation, noOtherPixelFired: noOtherPixelFiredExpectation)

        let defaults = makeUserDefaults()
        let bootDate = Date.distantPast

        let handler = VPNTunnelStartPixelHandler(eventHandler: validationHandler.eventHandler, systemBootDate: bootDate, userDefaults: defaults)
        handler.canFire = false

        handler.handle(.begin, onDemand: true)
        handler.handle(.success, onDemand: true)
        handler.handle(.begin, onDemand: true)
        handler.handle(.failure(NSError()), onDemand: true)

        waitForExpectations(timeout: 0.1)
    }
}
