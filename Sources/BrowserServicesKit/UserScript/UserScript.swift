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

public protocol UserScript: WKScriptMessageHandler {

    var source: String { get }
    var injectionTime: WKUserScriptInjectionTime { get }
    var forMainFrameOnly: Bool { get }
    var requiresRunInPageContentWorld: Bool { get }

    var messageNames: [String] { get }

    func makeWKUserScript() -> WKUserScript

}

extension UserScript {

    static public var requiresRunInPageContentWorld: Bool {
        return false
    }

    public var requiresRunInPageContentWorld: Bool {
        return false
    }

    @available(macOS 11.0, *)
    static func getContentWorld(_ requiresRunInPageContentWorld: Bool) -> WKContentWorld {
        if requiresRunInPageContentWorld {
            return .page
        }
        return .defaultClient
    }

    @available(macOS 11.0, *)
    public func getContentWorld() -> WKContentWorld {
        return Self.getContentWorld(requiresRunInPageContentWorld)
    }

    public static func loadJS(_ jsFile: String, from bundle: Bundle, withReplacements replacements: [String: String] = [:]) -> String {

        let path = bundle.path(forResource: jsFile, ofType: "js")!

        guard var js = try? String(contentsOfFile: path) else {
            fatalError("Failed to load JavaScript \(jsFile) from \(path)")
        }

        for (key, value) in replacements {
            js = js.replacingOccurrences(of: key, with: value, options: .literal)
        }

        return js
    }

    static func makeWKUserScript(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool, requiresRunInPageContentWorld: Bool = false) -> WKUserScript {
        if #available(macOS 11.0, iOS 14.0, *) {
            let contentWorld = getContentWorld(requiresRunInPageContentWorld)
            return WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly, in: contentWorld)
        } else {
            return WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly)
        }
    }

    public func makeWKUserScript() -> WKUserScript {
        return Self.makeWKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly, requiresRunInPageContentWorld: requiresRunInPageContentWorld)
    }

}
