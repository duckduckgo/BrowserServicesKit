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

public final class CrashReportSender {

    static let reportServiceUrl = URL(string: "https://loremattei.ngrok.app/crash.js")!
    //static let reportServiceUrl = URL(string: "https://duckduckgo.com/crash.js")!
    public let platform: CrashCollectionPlatform

    public init(platform: CrashCollectionPlatform) {
        self.platform = platform
    }

    public func send(_ crashReportData: Data) async {
        var request = URLRequest(url: Self.reportServiceUrl)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue(platform.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpMethod = "POST"
        request.httpBody = crashReportData

        do {
            _ = try await session.data(for: request)
        } catch {
            assertionFailure("CrashReportSender: Failed to send the crash report")
        }
    }

    private let session = URLSession(configuration: .ephemeral)
}
