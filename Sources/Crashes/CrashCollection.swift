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

    // Need a strong reference
    static let collector = CrashCollector()

    public static func collectCrashesAsync(completion: @escaping ([String: String]) -> Void) {
        collector.completion = completion
        MXMetricManager.shared.add(collector)
    }

    final class CrashCollector: NSObject, MXMetricManagerSubscriber {

        var completion: ([String: String]) -> Void = { _ in }

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            payloads
                .compactMap { $0.crashDiagnostics }
                .flatMap { $0 }
                .forEach {
                    completion([
                        "appVersion": "\($0.applicationVersion).\($0.metaData.applicationBuildVersion)",
                        "code": "\($0.exceptionCode ?? -1)",
                        "type": "\($0.exceptionType ?? -1)",
                        "signal": "\($0.signal ?? -1)"
                    ])
                }
        }

    }

    static let firstCrashKey = "CrashCollection.first"

    static var firstCrash: Bool {
        get {
            UserDefaults().object(forKey: Self.firstCrashKey) as? Bool ?? true
        }

        set {
            UserDefaults().set(newValue, forKey: Self.firstCrashKey)
        }
    }

    public static func start(firePixel: @escaping ([String: String]) -> Void) {
        let first = Self.firstCrash
        CrashCollection.collectCrashesAsync { params in
            var params = params
            if first {
                params["first"] = "1"
            }
            firePixel(params)
        }
        // Turn the flag off for next time
        Self.firstCrash = false
    }

}
