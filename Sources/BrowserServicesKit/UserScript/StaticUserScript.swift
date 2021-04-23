//
//  UserScript.swift
//  Core
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

import WebKit

public protocol StaticUserScript: UserScript {

    static var source: String { get }
    static var injectionTime: WKUserScriptInjectionTime { get }
    static var forMainFrameOnly: Bool { get }

    static var script: WKUserScript { get }

}

public extension StaticUserScript {

    var source: String {
        Self.source
    }

    var injectionTime: WKUserScriptInjectionTime {
        Self.injectionTime
    }

    var forMainFrameOnly: Bool {
        Self.forMainFrameOnly
    }

    func makeWKUserScript() -> WKUserScript {
        Self.script
    }

    static func makeWKUserScript() -> WKUserScript {
        return self.makeWKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly)
    }

}
