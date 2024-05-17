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

public enum CrashCollectionPlatform {
    case iOS, macOS, macOSAppStore

    var userAgent: String {
        switch self {
        case .iOS:
            return "ddg_ios"
        case .macOS:
            return "ddg_mac"
        case .macOSAppStore:
            return "ddg_mac_appstore"
        }
    }
}

@available(iOSApplicationExtension, unavailable)
@available(iOS 13, macOS 12, *)
public final class CrashCollection {

    public var log: OSLog {
        getLog()
    }
    private let getLog: () -> OSLog

    public init(platform: CrashCollectionPlatform, log: @escaping @autoclosure () -> OSLog = OSLog.disabled) {
        self.getLog = log
        crashHandler = CrashHandler()
        crashSender = CrashReportSender(platform: platform, log: log())
    }

    public func start(_ didFindCrashReports: @escaping (_ pixelParameters: [[String: String]], _ payloads: [MXDiagnosticPayload], _ uploadReports: @escaping () -> Void) -> Void) {
        let first = isFirstCrash
        isFirstCrash = false

        os_log("😵 Requesting diagnostics from MXMetricManager")
        crashHandler.crashDiagnosticsPayloadHandler = { payloads in
            os_log("😵 diagnostics callback %{public}s", "\(payloads)")
            for payload in payloads {
                var params = payload.dictionaryRepresentation()
                if let diagnostics = payload.crashDiagnostics {
                    for diagnostic in diagnostics {
                        if #available(macOS 14.0, *),
                           let reason = diagnostic.exceptionReason {
                            params["className"] = reason.className
                            params["composedMessage"] = reason.composedMessage
                            params["exceptionName"] = reason.exceptionName
                            params["exceptionType"] = reason.exceptionType
                        } else {
                            params["exceptionReason"] = "unavailable"
                        }

                        os_log("😵 crash: %{public}s", "\(params)")
                    }
                    continue
                } else {
                    params["crashDiagnostics"] = "unavailable"
                }
                os_log("😵 payload: %{public}s", "\(params)")
            }
            let pixelParameters = payloads
                .compactMap(\.crashDiagnostics)
                .flatMap { $0 }
                .map { diagnostic in
                    var params = [
                        "appVersion": "\(diagnostic.applicationVersion).\(diagnostic.metaData.applicationBuildVersion)",
                        "code": "\(diagnostic.exceptionCode ?? -1)",
                        "type": "\(diagnostic.exceptionType ?? -1)",
                        "signal": "\(diagnostic.signal ?? -1)",
                    ]
                    if first {
                        params["first"] = "1"
                    }
                    return params
                }
            didFindCrashReports(pixelParameters, payloads) {
                Task {
                    for payload in payloads {
                        await self.crashSender.send(payload.jsonRepresentation())
                    }
                }
            }
        }

        MXMetricManager.shared.add(crashHandler)
    }

    var isFirstCrash: Bool {
        get {
            UserDefaults().object(forKey: Const.firstCrashKey) as? Bool ?? true
        }

        set {
            UserDefaults().set(newValue, forKey: Const.firstCrashKey)
        }
    }

    let crashHandler: CrashHandler
    let crashSender: CrashReportSender

    enum Const {
        static let firstCrashKey = "CrashCollection.first"
    }
}
