//
//  CrashCollection.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import MetricKit

@available(iOSApplicationExtension, unavailable)
@available(iOS 13, macOS 12, *)
public struct CrashCollection {

    public enum Platform {
        case iOS, macOS
    }

    // Need a strong reference
    static let crashHandler = CrashHandler()
    static let crashSender = CrashReportSender()

    public static func start(platform: Platform,
                             firePixelHandler: @escaping ([String: String]) -> Void,
                             showPromptIfCanSendCrashReport: @escaping ( @escaping (Bool) -> Void ) -> Void) {

        CrashCollection.collectCrashesAsync { payloads in
            // Send pixels
            payloads
                .compactMap { $0.crashDiagnostics }
                .flatMap { $0 }
                .forEach {
                    firePixelHandler([
                        "appVersion": "\($0.applicationVersion).\($0.metaData.applicationBuildVersion)",
                        "code": "\($0.exceptionCode ?? -1)",
                        "type": "\($0.exceptionType ?? -1)",
                        "signal": "\($0.signal ?? -1)"
                    ])
                }

            // Show prompt to send crash reports
            showPromptIfCanSendCrashReport { canSend in
                print("-- sendCrashReportHandler { shouldSend : \(canSend)")
                if canSend {
                    // send all the payloads
                    payloads.forEach {
                        print("-- sending payload")
                        crashSender.send($0)
                    }
                }
            }
        }
    }

    private static func collectCrashesAsync(crashDiagnosticsPayloadHandler: @escaping ([MXDiagnosticPayload]) -> Void) {

        // TODO: Remove, only for testing

        class MockPayload: MXDiagnosticPayload {
            var mockCrashes: [MXCrashDiagnostic]?

            init(mockCrashes: [MXCrashDiagnostic]?) {
                self.mockCrashes = mockCrashes
                super.init()
            }

            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var crashDiagnostics: [MXCrashDiagnostic]? {
                return mockCrashes
            }
        }


        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let fakePayloads = [MockPayload(mockCrashes: nil),
                                MockPayload(mockCrashes: []),
                                MockPayload(mockCrashes: [MXCrashDiagnostic()]),
                                MockPayload(mockCrashes: [MXCrashDiagnostic(), MXCrashDiagnostic()])]

            crashHandler.didReceive(fakePayloads)
        }
        ////////////////////////////////////////////

        crashHandler.crashDiagnosticsPayloadHandler = crashDiagnosticsPayloadHandler

        MXMetricManager.shared.add(crashHandler)
    }
}


