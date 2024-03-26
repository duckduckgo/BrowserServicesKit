//
//  CrashReportSender.swift
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
import MetricKit
import Networking

@available(iOSApplicationExtension, unavailable)
@available(iOS 13, macOS 12, *)
final class CrashReportSender {

    static let reportServiceUrl = URL(string: "https://d4f4-20-53-134-160.ngrok-free.app/crash.js")!
    //    static let reportServiceUrl = URL(string: "https://duckduckgo.com/crash.js")!

    let platform: CrashCollection.Platform

    var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog

    init(platform: CrashCollection.Platform, log: @escaping @autoclosure () -> OSLog = .disabled) {
        self.platform = platform
        getLog = log
    }

    func send(_ payload: MXDiagnosticPayload) async {
        var request = URLRequest(url: Self.reportServiceUrl)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue(platform.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpMethod = "POST"
        request.httpBody = payload.jsonRepresentation()

        do {
            _ = try await session.data(for: request)
        } catch {
            assertionFailure("CrashReportSender: Failed to send the crash reprot")
        }
    }

    private let session = URLSession(configuration: .ephemeral)
}

@available(iOSApplicationExtension, unavailable)
@available(iOS 13, macOS 12, *)
extension CrashCollection.Platform {
    var userAgent: String {
        switch self {
        case .iOS:
            return "ddg_ios"
        case .macOS:
            return "ddg_mac"
        }
    }
}
