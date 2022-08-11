//
//  TLD.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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

public class TLD {

    private(set) var tlds: Set<String> = []

    var json: String {
        guard let data = try? JSONEncoder().encode(tlds) else { return "[]" }
        guard let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    public init() {
        guard let url = Bundle.module.url(forResource: "tlds", withExtension: "json") else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        
        let asString = String(decoding: data, as: UTF8.self)
        let asStringWithoutComments = asString.replacingOccurrences(of: "(?m)^//.*",
                                                                    with: "",
                                                                    options: .regularExpression)
        guard let cleanedData: Data = asStringWithoutComments.data(using: .utf8) else { return }
        
        guard let tlds = try? JSONDecoder().decode([String].self, from: cleanedData) else { return }
        self.tlds = Set(tlds)
    }

    public func domain(_ host: String?) -> String? {
        guard let host = host else { return nil }

        let parts = [String](host.components(separatedBy: ".").reversed())
        
        guard let lastComponent = parts.first, tlds.contains(lastComponent) else {
            return nil
        }
        var stack = lastComponent

        for index in 1 ..< parts.count {
            let part = parts[index]
            stack = !stack.isEmpty ? part + "." + stack : part
            guard tlds.contains(stack) else { break }
        }

        return stack
    }

    public func eTLDplus1(_ host: String?) -> String? {
        guard let domain = domain(host), !tlds.contains(domain) else { return nil }
        return domain
    }
    
}
