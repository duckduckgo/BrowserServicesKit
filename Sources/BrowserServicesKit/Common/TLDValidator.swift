//
//  TLDValidator.swift
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
import DomainParser

struct TLDValidator {
    let domainParser: DomainParser

    static let shared: TLDValidator = .init()

    private init() {
        // swiftlint:disable:next implicitly_unwrapped_optional
        let pslFileURL = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat")!

        // swiftlint:disable:next force_try
        domainParser = try! DomainParser(pslFileURL: pslFileURL, quickParsing: true)
    }

    func isHostnameWithValidTLD(_ hostname: String) -> Bool {
        return domainParser.parse(host: hostname)?.domain != nil
    }
}
