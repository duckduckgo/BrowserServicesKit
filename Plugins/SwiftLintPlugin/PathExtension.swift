//
//  PathExtension.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import PackagePlugin

extension Path {

    static let mv = Path("/bin/mv")
    static let echo = Path("/bin/echo")
    static let cat = Path("/bin/cat")
    static let sh = Path("/bin/sh")

    /// Get file modification date
    var modified: Date {
        get throws {
            try FileManager.default.attributesOfItem(atPath: self.string)[.modificationDate] as? Date ?? { throw CocoaError(.fileReadUnknown) }()
        }
    }

    var url: URL {
        URL(fileURLWithPath: self.string)
    }

}
