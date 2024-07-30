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

    /// "exporting" `OSLog.disabled` symbol without needing to `import os.log` to disambiguate `os_log` wrapper calls and suppress "implicit import" warning
    /// this declaration shadows the real `OSLog.disabled`
    public static let disabled: OSLog = {
        // the `OSLog` object returned by `OSLog.disabled` is in fact an `os_log_t *` pointer defined by C `_os_log_disabled` symbol
        guard let disabledLog = dlsym(/*RTLD_DEFAULT*/ UnsafeMutableRawPointer(bitPattern: -2), "_os_log_disabled") else {
            // just in case it fails for whatever reason (but it shouldn‘t) - return some log object
            assertionFailure("_os_log_disabled symbol not found")
            return .init(subsystem: "", category: "")
        }
        return unsafeBitCast(disabledLog, to: OSLog.self)
    }()

    public enum Categories: String, CaseIterable {
        case contentBlocking = "Content Blocking"
        case userScripts = "User Scripts"
        case passwordManager = "Password Manager"
        case remoteMessaging = "Remote Messaging"
        case subscription = "Subscription"
        case phishingDetection = "PhishingDetection"
        case history = "History"
        case general = "General"
        case autofill = "Autofill"
    }

#if DEBUG
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    // To activate Logging Categories for DEBUG add categories here:
    static var debugCategories: Set<Categories> = [ /*.autofill*/ ]
#endif

    @OSLogWrapper(.contentBlocking)     public static var contentBlocking
    @OSLogWrapper(.userScripts)         public static var userScripts
    @OSLogWrapper(.passwordManager)     public static var passwordManager
    @OSLogWrapper(.remoteMessaging)     public static var remoteMessaging
    @OSLogWrapper(.subscription)        public static var subscription
    @OSLogWrapper(.phishingDetection)   public static var phishingDetection
    @OSLogWrapper(.history)             public static var history
    @OSLogWrapper(.general)             public static var general
    @OSLogWrapper(.autofill)            public static var autofill

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

// MARK: - message first

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType) {
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif
    os.os_log(message, log: log, type: type)
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog) {
    os.os_log(message, log: log, type: .default)
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1())
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1(), arg2())
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3())
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg, _ arg4: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3(), arg4())
}

@inlinable
public func os_log(_ message: StaticString, log: OSLog = .default, type: OSLogType = .default, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg, _ arg4: @autoclosure () -> some CVarArg, _ arg5: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3(), arg4(), arg5())
}

public enum LogVisibility {
    case `private`
    case `public`
}

@inlinable
public func os_log(_ visibility: LogVisibility, _ message: @autoclosure () -> String, log: OSLog = .default, type: OSLogType = .default) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

#if !DEBUG
    if visibility == .private {
        os_log("%s", log: log, type: type, message())
        return
    }
#endif
    // always log to Console app (public) in DEBUG
    os_log("%{public}s", log: log, type: type, message())
}

@inlinable
@_disfavoredOverload
public func os_log(_ message: @autoclosure () -> String, log: OSLog = .default, type: OSLogType = .default) {
    os_log(.private, message(), log: log, type: type)
}

// MARK: - type first

@inlinable
public func os_log(_ type: OSLogType, log: OSLog = .default, _ message: StaticString) {
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

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
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1())
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1(), arg2())
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3())
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg, _ arg4: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3(), arg4())
}

@inlinable
public func os_log(_ type: OSLogType = .default, log: OSLog = .default, _ message: StaticString, _ arg1: @autoclosure () -> some CVarArg, _ arg2: @autoclosure () -> some CVarArg, _ arg3: @autoclosure () -> some CVarArg, _ arg4: @autoclosure () -> some CVarArg, _ arg5: @autoclosure () -> some CVarArg) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

    os.os_log(message, log: log, type: type, arg1(), arg2(), arg3(), arg4(), arg5())
}

@inlinable
@_disfavoredOverload
public func os_log(_ type: OSLogType, log: OSLog, _ message: @autoclosure () -> String, _ visibility: LogVisibility = .private) {
    guard log != .disabled else { return }
#if DEBUG
    // enable .debug/.info logging in DEBUG builds
    let type = OSLogType(min(type.rawValue, OSLogType.default.rawValue))
#endif

#if !DEBUG
    if visibility == .private {
        os_log("%s", log: log, type: type, message())
        return
    }
#endif
    // always log to Console app (public) in DEBUG
    os_log("%{public}s", log: log, type: type, message())
}

@inlinable
@_disfavoredOverload
public func os_log(log: OSLog, _ message: @autoclosure () -> String, _ visibility: LogVisibility = .private) {
    os_log(.default, log: log, message(), visibility)
}

@inlinable
@_disfavoredOverload
public func os_log(_ type: OSLogType, _ message: @autoclosure () -> String, _ visibility: LogVisibility = .private) {
    os_log(type, log: .default, message(), visibility)
}

@inlinable
@_disfavoredOverload
public func os_log(_ message: @autoclosure () -> String, _ visibility: LogVisibility = .private) {
    os_log(.default, log: .default, message(), visibility)
}
