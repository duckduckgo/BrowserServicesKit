//
//  CrashHandler.swift
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
final class CrashHandler: NSObject, MXMetricManagerSubscriber {

    var firePixelHandler: ([String: String]) -> Void = { _ in }
    var crashDiagnosticsPayloadHandler: ([MXDiagnosticPayload]) -> Void = { _ in }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let payloadsWithCrash = payloads.filter { !($0.crashDiagnostics?.isEmpty ?? true) }

        payloadsWithCrash
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

        crashDiagnosticsPayloadHandler(payloadsWithCrash)
    }

}
