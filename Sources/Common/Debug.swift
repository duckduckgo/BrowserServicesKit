//
//  Debug.swift
//  DuckDuckGo
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
import os.log

public func breakByRaisingSigInt(_ description: String, file: StaticString = #file, line: Int = #line) {
    let fileLine = "\(("\(file)" as NSString).lastPathComponent):\(line)"
    os_log("""


    ------------------------------------------------------------------------------------------------------
        BREAK at %s:
    ------------------------------------------------------------------------------------------------------

    %s

        Hit Continue (^⌘Y) to continue program execution
    ------------------------------------------------------------------------------------------------------

    """, type: .debug, fileLine, description.components(separatedBy: "\n").map { "    " + $0.trimmingWhitespace() }.joined(separator: "\n"))
    raise(SIGINT)
}
