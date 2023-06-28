//
//  Logging.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import os // swiftlint:disable:this enforce_os_log_wrapper

public typealias OSLog = os.OSLog

extension OSLog {

    public static let disabled = os.OSLog.disabled

    public enum Categories: String, CaseIterable {
        case userScripts = "User Scripts"
        case passwordManager = "Password Manager"
        case remoteMessaging = "Remote Messaging"
    }

#if DEBUG
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    // To activate Logging Categories for DEBUG add categories here:
    static var debugCategories: Set<Categories> = [ /* .userScripts, */ ]
#endif

    @OSLogWrapper(.userScripts)     public static var userScripts
    @OSLogWrapper(.passwordManager) public static var passwordManager
    @OSLogWrapper(.remoteMessaging) public static var remoteMessaging

    public static var enabledLoggingCategories = Set<String>()

    static let isRunningInDebugEnvironment: Bool = {
        ProcessInfo().environment[ProcessInfo.Constants.osActivityMode] == ProcessInfo.Constants.debug
            || ProcessInfo().environment[ProcessInfo.Constants.osActivityDtMode] == ProcessInfo.Constants.yes
    }()

    static let subsystem = Bundle.main.bundleIdentifier ?? "DuckDuckGo"

    @propertyWrapper
    public struct OSLogWrapper {

        public let category: String

        public init(rawValue: String) {
            self.category = rawValue
        }

        public var wrappedValue: OSLog {
            var isEnabled = OSLog.enabledLoggingCategories.contains(category)
#if CI
            isEnabled = true
#elseif DEBUG
            isEnabled = isEnabled || Categories(rawValue: category).map(OSLog.debugCategories.contains) == true
#endif

            return isEnabled ? OSLog(subsystem: OSLog.subsystem, category: category) : .disabled
        }

    }

}

public extension OSLog.OSLogWrapper {

    init(_ category: OSLog.Categories) {
        self.init(rawValue: category.rawValue)
    }

}

extension ProcessInfo {
    enum Constants {
        static let osActivityMode = "OS_ACTIVITY_MODE"
        static let osActivityDtMode = "OS_ACTIVITY_DT_MODE"
        static let debug = "debug"
        static let yes = "YES"
    }
}

// swiftlint:disable line_length
// swiftlint:disable function_parameter_count

// MARK: - message first

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType) {
    os.os_log(message, log: log, type: type)
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog) {
    os.os_log(message, log: log, type: .default)
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1())
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1(), arg2())
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3())
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg, _ arg4: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3(), arg4())
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg, _ arg4: @autoclosure () -> some CVarArg, _ arg5: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3(), arg4(), arg5())
}

@inlinable
@_disfavoredOverload
public func os_log(_ message: @autoclosure () -> String, log: OSLog = .default, type: OSLogType = .default) {
    guard log != .disabled else { return }
    os_log("%s", log: log, type: type, message())
}

// MARK: - type first

@inlinable
public func os_log(_ type: OSLogType, log: OSLog = .default, _ message: StaticString) {
    os.os_log(message, log: log, type: type)
}

@inlinable
public func os_log(log: OSLog, _ message: StaticString) {
    os.os_log(message, log: log, type: .default)
}

@inlinable
public func os_log(_ message: StaticString) {
    os.os_log(message, log: .default, type: .default)
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1())
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1(), arg2())
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3())
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg, _ arg4: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3(), arg4())
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg, _ arg4: @autoclosure () -> some CVarArg, _ arg5: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3(), arg4(), arg5())
}

@inlinable
@_disfavoredOverload
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: @autoclosure () -> String) {
    guard log != .disabled else { return }
    os_log("%s", log: log, type: type, message())
}

// swiftlint:enable line_length
// swiftlint:enable function_parameter_count
