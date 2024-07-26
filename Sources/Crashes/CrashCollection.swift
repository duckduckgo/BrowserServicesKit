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

    public init(platform: CrashCollectionPlatform, log: @escaping @autoclosure () -> OSLog = .disabled) {
        self.getLog = log
        crashHandler = CrashHandler()
        crashSender = CrashReportSender(platform: platform, log: log())
    }

    public func start(didFindCrashReports: @escaping (_ pixelParameters: [[String: String]], _ payloads: [Data], _ uploadReports: @escaping () -> Void) -> Void) {
        start(process: { payloads in
            payloads.map { $0.jsonRepresentation() }
        }, didFindCrashReports: didFindCrashReports)
    }

    public func start(process: @escaping ([MXDiagnosticPayload]) -> [Data], didFindCrashReports: @escaping (_ pixelParameters: [[String: String]], _ payloads: [Data], _ uploadReports: @escaping () -> Void) -> Void) {
        let first = isFirstCrash
        isFirstCrash = false

        crashHandler.crashDiagnosticsPayloadHandler = { [log] payloads in
            os_log("😵 loaded %{public}d diagnostic payloads", log: log, payloads.count)
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
            let processedData = process(payloads)
            didFindCrashReports(pixelParameters, processedData) {
                Task {
                    for payload in processedData {
                        await self.crashSender.send(payload)
                    }
                }
            }
        }

        MXMetricManager.shared.add(crashHandler)
    }

    public func startAttachingCrashLogMessages(didFindCrashReports: @escaping (_ pixelParameters: [[String: String]], _ payloads: [Data], _ uploadReports: @escaping () -> Void) -> Void) {
        start(process: { payloads in
            payloads.compactMap { payload in
                var dict = payload.dictionaryRepresentation()

                var pid: pid_t?
                if #available(macOS 14.0, iOS 17.0, *) {
                    pid = payload.crashDiagnostics?.first?.metaData.pid
                }
                if var crashDiagnostics = dict["crashDiagnostics"] as? [[AnyHashable: Any]], !crashDiagnostics.isEmpty {
                    var crashDiagnosticsDict = crashDiagnostics[0]
                    var diagnosticMetaDataDict = crashDiagnosticsDict["diagnosticMetaData"] as? [AnyHashable: Any] ?? [:]
                    var objCexceptionReason = diagnosticMetaDataDict["objectiveCexceptionReason"] as? [AnyHashable: Any] ?? [:]

                    var exceptionMessage = (objCexceptionReason["composedMessage"] as? String)?.sanitized()
                    var stackTrace: [String]?

                    // append crash log message if loaded
                    if let diagnostic = try? CrashLogMessageExtractor().crashDiagnostic(for: payload.timeStampBegin, pid: pid)?.diagnosticData(), !diagnostic.isEmpty {
                        if let existingMessage = exceptionMessage, !existingMessage.isEmpty {
                            exceptionMessage = existingMessage + "\n\n---\n\n" + diagnostic.message
                        } else {
                            exceptionMessage = diagnostic.message
                        }
                        stackTrace = diagnostic.stackTrace
                    }

                    objCexceptionReason["composedMessage"] = exceptionMessage
                    objCexceptionReason["stackTrace"] = stackTrace
                    diagnosticMetaDataDict["objectiveCexceptionReason"] = objCexceptionReason
                    crashDiagnosticsDict["diagnosticMetaData"] = diagnosticMetaDataDict
                    crashDiagnostics[0] = crashDiagnosticsDict
                    dict["crashDiagnostics"] = crashDiagnostics
                }

                guard JSONSerialization.isValidJSONObject(dict) else {
                    assertionFailure("Invalid JSON object: \(dict)")
                    return nil
                }
                return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            }

        }, didFindCrashReports: didFindCrashReports)
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
