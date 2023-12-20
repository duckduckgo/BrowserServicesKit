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

@available(iOSApplicationExtension, unavailable)
@available(iOS 13, macOS 12, *)
final class CrashReportSender {

    static let reportServiceUrl = URL(string: "https://duckduckgo.com/crash.js")!

    private let session = URLSession(configuration: .ephemeral)

    func send(_ payload: MXDiagnosticPayload) {
        var request = URLRequest(url: Self.reportServiceUrl)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        // TODO: Parametrize the useragent
        request.setValue("ddg_ios", forHTTPHeaderField: "User-Agent")
        request.httpMethod = "POST"
        request.httpBody = payloadAsData(payload)

        session.dataTask(with: request) { (_, _, error) in
            if error != nil {
                assertionFailure("CrashReportSender: Failed to send the crash report")
            }
        }.resume()
    }

    private func payloadAsData(_ crashReport: MXDiagnosticPayload) -> Data {
        return crashReport.jsonRepresentation()
    }

}
