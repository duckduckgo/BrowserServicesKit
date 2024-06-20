//
//  CrashLogMessageExtractor.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import cxxCrashHandler
import Foundation

/// Collects crash diagnostic messages (NSException/C++ exception name, description and stack trace) and saves to file:
/// `applicationSupportDir/Diagnostics/2024-05-20T12:11:33Z-%pid%.log`
public struct CrashLogMessageExtractor {

    private struct CrashLog {

        // ""2024-05-22T08:17:23Z59070.log"
        static let fileNameRegex = regex(#"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[+-][0-2]\d:[0-5]\d|Z))-(\d+)\.log$"#)

        let url: URL
        let timestamp: Date
        let pid: pid_t

        init?(url: URL) {
            let fileName = url.lastPathComponent

            guard let match = Self.fileNameRegex.firstMatch(in: fileName, range: fileName.fullRange),
                  match.numberOfRanges >= 3 else { return nil }

            let dateNsRange = match.range(at: 1)
            let pidNsRange = match.range(at: 2)
            guard dateNsRange.location != NSNotFound, pidNsRange.location != NSNotFound,
                  let dateRange = Range(dateNsRange, in: fileName),
                  let pidRange = Range(pidNsRange, in: fileName),
                  let timestamp = ISO8601DateFormatter().date(from: String(fileName[dateRange])),
                  let pid = pid_t(fileName[pidRange])
            else { return nil }

            self.url = url
            self.timestamp = timestamp
            self.pid = pid
        }
    }

    fileprivate static var nextUncaughtExceptionHandler: NSUncaughtExceptionHandler!
    fileprivate static var nextCppTerminateHandler: (() -> Void)!
    fileprivate static var diagnosticsDirectory: URL!

    public static func setUp() {
        prepareDiagnosticsDirectory()

        // Set unhandled NSException handler
        nextUncaughtExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(handleException)
        // Set unhandled C++ exception handler
        nextCppTerminateHandler = SetCxxExceptionTerminateHandler(handleCxxException)
        // Swap C++ `throw` to collect stack trace when throw happens
        kscm_enableSwapCxaThrow()
    }

    /// create App Support/Diagnostics folder
    private static func prepareDiagnosticsDirectory() {
        let fm = FileManager.default
        let diagnosticsUrl = fm.diagnosticsDirectory
        try? fm.createDirectory(at: diagnosticsUrl, withIntermediateDirectories: true)
        Self.diagnosticsDirectory = diagnosticsUrl
    }

    /// Find saved crash diagnostics message for crash PID/timestamp
    public static func crashLogMessage(for timestamp: Date?, pid: pid_t?) -> String? {
        let fm = FileManager.default
        let diagDir = fm.diagnosticsDirectory
        guard timestamp != nil || pid != nil,
              var crashLogs = try? fm.contentsOfDirectory(atPath: diagDir.path).compactMap({ CrashLog(url: diagDir.appending($0)) }) else { return nil }

        if let pid, pid > 0 {
            // filter by Process Identifier if it‘s known
            crashLogs = crashLogs.filter { $0.pid == pid }
        }

        // sort by distance from the crash timestamp, take the closest
        let timestamp = timestamp ?? Date()
        let crashLog = crashLogs.sorted { (lhs: CrashLog, rhs: CrashLog) in
            Swift.abs(timestamp.timeIntervalSince(lhs.timestamp)) < Swift.abs(timestamp.timeIntervalSince(rhs.timestamp))
        }.first

        guard let crashLog else {
            os_log("😵 no crash logs found for %{public}s/%d", ISO8601DateFormatter().string(from: timestamp), pid ?? 0)
            return nil
        }
        // allow max of 3s timestamp difference when no pid available
        guard pid != nil || Swift.abs(timestamp.timeIntervalSince(crashLog.timestamp)) <= 3 else {
            os_log("😵 closest crashlog %{public}s differs from %{public}s by %dms", crashLog.url.lastPathComponent, ISO8601DateFormatter().string(from: timestamp), Swift.abs(timestamp.timeIntervalSince(crashLog.timestamp)))
            return nil
        }

        do {
            let message = try String(contentsOf: crashLog.url)
            return message
        } catch {
            os_log("😵 could not read contents of %{public}s: %s", crashLog.url.lastPathComponent, error.localizedDescription)
            return nil
        }
    }

}

// `std::terminate` C++ unhandled exception handler
private func handleCxxException() {
    // convert C++ exception to NSException (with name, description and stack trace) and handle it
    if let exception = NSException.currentCxxException() {
        handleException(exception)
    }
    // default handler
    CrashLogMessageExtractor.nextCppTerminateHandler()
}

// NSUncaughtExceptionHandler
private func handleException(_ exception: NSException) {
    os_log(.error, "Trapped exception \(exception)")

    // collect exception diagnostics data
    let message = """
    \(exception.name.rawValue): \(exception.reason ?? "")
    \(exception.userInfo.map { $0.description + "\n" } ?? "")[
      \(exception.callStackSymbols.joined(separator: ",\n  "))
    ]
    """.sanitized() // clean-up possible filenames and emails

    // save crash log with `2024-05-20T12:11:33Z-%pid%.log` file name format
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let fileName = "\(timestamp)-\(ProcessInfo().processIdentifier).log"
    let fileURL = CrashLogMessageExtractor.diagnosticsDirectory.appendingPathComponent(fileName)

    try? message.utf8data.write(to: fileURL)

    // default handler
    CrashLogMessageExtractor.nextUncaughtExceptionHandler(exception)
}

/// Throw test C++ exception – used for debug purpose
public func throwTestCppExteption() {
    _throwTestCppException("This a test C++ exception")
}

private extension FileManager {
    var diagnosticsDirectory: URL {
        applicationSupportDirectoryForComponent(named: "Diagnostics")
    }
}
