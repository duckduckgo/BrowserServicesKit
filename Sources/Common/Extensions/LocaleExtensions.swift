//
//  LocaleExtensions.swift
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
//  Implementation guidelines: https://app.asana.com/0/1198207348643509/1200202563872939/f

import Foundation

public extension Locale {
    var localeIdentifierAsJsonFormat: String {
        let baseIdentifier = self.identifier.components(separatedBy: "@").first ?? self.identifier
        return baseIdentifier.replacingOccurrences(of: "_", with: "-")
    }
}