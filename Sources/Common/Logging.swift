//
//  Logging.swift
//  DuckDuckGo
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
import os

public typealias OSLog = os.OSLog

extension OSLog {

    public static var userScripts: OSLog {
        Logging.userScriptsEnabled ? Logging.userScriptsLog : .disabled
    }
    
    public static var passwordManager: OSLog {
        Logging.passwordManagerEnabled ? Logging.passwordManagerLog : .disabled
    }

    public static var remoteMessaging: OSLog {
        Logging.remoteMessagingEnabled ? Logging.remoteMessagingLog : .disabled
    }

}

struct Logging {

    fileprivate static let userScriptsEnabled = false
    fileprivate static let userScriptsLog: OSLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "User Scripts")
    
    fileprivate static let passwordManagerEnabled = false
    fileprivate static let passwordManagerLog: OSLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "Password Manager")

    fileprivate static let remoteMessagingEnabled = false
    fileprivate static let remoteMessagingLog: OSLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "Remote Messaging")

}

// swiftlint:disable line_length

// MARK : - message first

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
public func os_log(message: @autoclosure () -> String, log: OSLog = .default, type: OSLogType = .default) {
    guard log != .disabled else { return }
    os_log("%s", log: log, type: type, message())
}

// MARK : - type first

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
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, message: @autoclosure () -> String) {
    guard log != .disabled else { return }
    os_log("%s", log: log, type: type, message())
}

// swiftlint:enable line_length
