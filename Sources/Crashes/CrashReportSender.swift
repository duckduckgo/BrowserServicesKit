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

public protocol CrashReportSending {
    init(platform: CrashCollectionPlatform)
    func send(_ crashReportData: Data, crcid: String?) async -> Result<Data?, Error>
    func send(_ crashReportData: Data, crcid: String?, completion: @escaping (Result<Data?, Error>) -> Void)
}

enum CrashReportSenderError: Error {
    case invalidResponse
}

// By conforming to a protocol, we can sub in mocks more easily
public final class CrashReportSender: CrashReportSending {

    static let reportServiceUrl = URL(string: "https://duckduckgo.com/crash.js")!
    public let platform: CrashCollectionPlatform
    
    private let session = URLSession(configuration: .ephemeral)

    public init(platform: CrashCollectionPlatform) {
        self.platform = platform
    }

    public func send(_ crashReportData: Data, crcid: String?, completion: @escaping (Result<Data?, Error>) -> Void) {
        var request = URLRequest(url: Self.reportServiceUrl)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue(platform.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpMethod = "POST"
        request.httpBody = crashReportData
        
        Logger.general.debug("CrashReportSender: Awaiting session data")
        let task = session.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse {
                Logger.general.debug("CrashReportSender: Received HTTP response code: \(response.statusCode)")
                if response.statusCode == 200 {
                    response.allHeaderFields.forEach { print("\($0.key): \($0.value)") }
                } else {
                    assertionFailure("CrashReportSender: Failed to send the crash report: \(response.statusCode)")
                }
                
                if let data {
                    completion(.success(data))
                } else if let error {
                    completion(.failure(error))
                } else {
                    completion(.failure(CrashReportSenderError.invalidResponse))
                }
            } else {
                    completion(.failure(CrashReportSenderError.invalidResponse))
            }
        }
        task.resume()
    }
    
    public func send(_ crashReportData: Data, crcid: String?) async -> Result<Data?, Error> {
        await withCheckedContinuation { continuation in
            send(crashReportData, crcid: crcid) { result in
                continuation.resume(returning: (result))
            }
        }
    }
    
    static let crashReportCohortIDKey = "CrashReportSender.crashReportCohortID"
    var crashReportCohortID: String? {
        get {
            if let crcid = UserDefaults().string(forKey: CrashReportSender.crashReportCohortIDKey) {
                return crcid
            } else {
                return nil
            }
        }
        set {
            UserDefaults().setValue(newValue, forKey: CrashReportSender.crashReportCohortIDKey)
        }
    }
}
