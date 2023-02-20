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

import Foundation
import WebKit
import CryptoKit

public protocol UserScript: WKScriptMessageHandler {

    var source: String { get }
    var injectionTime: WKUserScriptInjectionTime { get }
    var forMainFrameOnly: Bool { get }
    var requiresRunInPageContentWorld: Bool { get }

    var messageNames: [String] { get }

    func makeWKUserScript() -> WKUserScript

}

public protocol InteractiveUserScript: UserScript {
    var scriptDidLoadMessageName: DidLoadMessageName { get }
}

public struct DidLoadMessageName: RawRepresentable {
    public let rawValue: String = { "did_load_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_") }()
    public init() {}
    public init?(rawValue: String) { nil }

    public static func == (lhs: String, rhs: DidLoadMessageName) -> Bool {
        return lhs == rhs.rawValue
    }
}

extension UserScript {

    static public var requiresRunInPageContentWorld: Bool {
        return false
    }

    public var requiresRunInPageContentWorld: Bool {
        return false
    }

    @available(macOS 11.0, iOS 14.0, *)
    static func getContentWorld(_ requiresRunInPageContentWorld: Bool) -> WKContentWorld {
        if requiresRunInPageContentWorld {
            return .page
        }
        return .defaultClient
    }

    @available(macOS 11.0, iOS 14.0, *)
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

    static func makeWKUserScript(source: String, injectionTime: WKUserScriptInjectionTime,
                                 forMainFrameOnly: Bool, didLoadMessageName: DidLoadMessageName?,
                                 requiresRunInPageContentWorld: Bool = false) -> WKUserScript {
        let hash = SHA256.hash(data: Data(source.utf8)).hashValue

        let shouldRun = !source.contains("sjcl")
        // send didLoad message when the script was added
        let scriptDidLoad = didLoadMessageName.map { "webkit.messageHandlers.\($0.rawValue).postMessage({})" } ?? ""
        // This prevents the script being executed twice which appears to be a WKWebKit issue for about:blank frames when the location changes
        let sourceOut = """
        (() => {
        
                 if (window.navigator._duckduckgoloader_ && window.navigator._duckduckgoloader_.includes('\(hash)')) {return}
        if (\(shouldRun)) {return}
                 \(source)
        
        Object.defineProperty(window.navigator, '_duckduckgoloader_', {
        value: window.navigator._duckduckgoloader_ || [],
        enumerable: false
        })
                 \(scriptDidLoad)
        /*
        if (!window.navigator.checkerDDG) {
                window.navigator.checkerDDG = true;
        const inspectKeys = Object.keys(window).filter((a) => {return a.startsWith('webkit') || a.startsWith('safari')  || a.startsWith('navigator')})
        //const inspectKeys = Object.keys(window)
        console.log({inspectKeys})
        function wrap(global, key, val) {
          if (val === undefined) { return val }
          if (!Object.is(returnVal) && !(typeof returnVal === 'function')) {return val }
        console.log('err', new Error().stack)
          return new Proxy(val, {
            get(...args) {
              console.log(`global.${key}.get`, args[1], document.currentScript); //, new Error().stack);
              const returnVal = Reflect.get(...args)
              if (Object.is(returnVal) || typeof returnVal === 'function') { return wrap('global', key+'.get', returnVal)}
              return returnVal
            },
            set() {
              console.log(`window.${key}.set`, ...args); //, new Error().stack);
              return Reflect.set(...args)
            },
            apply() {
              console.log(`window.${key}.apply`, ...args); //, new Error().stack);
              return Reflect.apply(...args)
            },
          });
        }
        
        for (let key of inspectKeys) {
        const val = window[key]
        // console.log({key, val})
        if (val === undefined) { continue }
        window[key] = new Proxy(val, {
          get(...args) {
            console.log(`window.${key}.get`, args[1], document.currentScript, new Error().stack);
            return wrap(`window`, key, Reflect.get(...args))
          },
          set() {
            console.log(`window.${key}.set`, ...args); //, new Error().stack);
            return Reflect.set(...args)
          },
          apply() {
            console.log(`window.${key}.apply`, ...args); //, new Error().stack);
            return Reflect.apply(...args)
          },
        });
        }
        }
        */
        })()
        """
        /*
         if (window.navigator._duckduckgoloader_ && window.navigator._duckduckgoloader_.includes('\(hash)')) {return}
         \(source)
         window.navigator._duckduckgoloader_ = window.navigator._duckduckgoloader_ || [];
         window.navigator._duckduckgoloader_.push('\(hash)')
         \(scriptDidLoad)
         */

        if #available(macOS 11.0, iOS 14.0, *) {
            let contentWorld = getContentWorld(requiresRunInPageContentWorld)
            return WKUserScript(source: sourceOut, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly, in: contentWorld)
        } else {
            return WKUserScript(source: sourceOut, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly)
        }
    }

    public func makeWKUserScript() -> WKUserScript {
        return Self.makeWKUserScript(source: source,
                                     injectionTime: injectionTime,
                                     forMainFrameOnly: forMainFrameOnly,
                                     didLoadMessageName: (self as? InteractiveUserScript)?.scriptDidLoadMessageName,
                                     requiresRunInPageContentWorld: requiresRunInPageContentWorld)
    }

}
