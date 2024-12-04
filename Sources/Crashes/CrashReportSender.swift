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
    func send(_ crashReportData: Data, crcid: String?) async -> (result: Result<Data?, Error>, response: HTTPURLResponse?)
    func send(_ crashReportData: Data, crcid: String?, completion: @escaping (_ result: Result<Data?, Error>, _ response: HTTPURLResponse?) -> Void)
}

enum CrashReportSenderError: Error {
    case invalidResponse
}

// By conforming to a protocol, we can sub in mocks more easily
public final class CrashReportSender: CrashReportSending {

#if DEBUG
    // TODO: Why is a breakpoint here hit twice?
    static let reportServiceUrl = URL(string: "https://9e3c-20-75-144-152.ngrok-free.app/crash.js")!
#else
    static let reportServiceUrl = URL(string: "https://duckduckgo.com/crash.js")!
#endif
    static let httpHeaderCRCID = "crcid"
    
    public let platform: CrashCollectionPlatform
    
    private let session = URLSession(configuration: .ephemeral)

    public init(platform: CrashCollectionPlatform) {
        self.platform = platform
    }

    public func send(_ crashReportData: Data, crcid: String?, completion: @escaping (_ result: Result<Data?, Error>, _ response: HTTPURLResponse?) -> Void) {
        var request = URLRequest(url: Self.reportServiceUrl)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue(platform.userAgent, forHTTPHeaderField: "User-Agent")
        if let crcid {
            request.setValue(crcid, forHTTPHeaderField: CrashReportSender.httpHeaderCRCID)
            Logger.general.debug("Configured crash report HTTP request with crcid: \(crcid)")
        }
        request.httpMethod = "POST"
        request.httpBody = crashReportData
        
        Logger.general.debug("CrashReportSender: Awaiting session data")
        let task = session.dataTask(with: request) { data, response, error in
            // TODO: Consider pixels for failures that mean we may have lost crash info?
            if let response = response as? HTTPURLResponse {
                Logger.general.debug("CrashReportSender: Received HTTP response code: \(response.statusCode)")
                if response.statusCode == 200 {
                    response.allHeaderFields.forEach { print("\($0.key): \($0.value)") }    // TODO: Why do we straight-up print these, rather than debug logging?
                } else {
                    assertionFailure("CrashReportSender: Failed to send the crash report: \(response.statusCode)")
                }
                
                if let data {
                    completion(.success(data), response)
                } else if let error {
                    completion(.failure(error), response)
                } else {
                    completion(.failure(CrashReportSenderError.invalidResponse), response)
                }
            } else {
                completion(.failure(CrashReportSenderError.invalidResponse), nil)
            }
        }
        task.resume()
    }
    
    public func send(_ crashReportData: Data, crcid: String?) async -> (result: Result<Data?, Error>, response: HTTPURLResponse?) {
        await withCheckedContinuation { continuation in
            send(crashReportData, crcid: crcid) { result, response in
                continuation.resume(returning: (result, response))
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
