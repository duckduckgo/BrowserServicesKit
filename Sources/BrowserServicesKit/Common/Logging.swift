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

extension OSLog {

    static var userScripts: OSLog {
        Logging.userScriptsEnabled ? Logging.userScriptsLog : .disabled
    }
    
    static var passwordManager: OSLog {
        Logging.passwordManagerEnabled ? Logging.passwordManagerLog : .disabled
    }

}

struct Logging {

    fileprivate static let userScriptsEnabled = false
    fileprivate static let userScriptsLog: OSLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "User Scripts")
    
    fileprivate static let passwordManagerEnabled = false
    fileprivate static let passwordManagerLog: OSLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "Password Manager")

}
