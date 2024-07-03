//
//  segment_command+helpers.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import Foundation

extension UnsafePointer where Pointee == segment_command_64 {

    var segname: String {
        String(cString: UnsafeRawPointer(pointer(to: \.segname))!.assumingMemoryBound(to: CChar.self))
    }

    var sections: UnsafeBufferPointer<section_64> {
        UnsafeBufferPointer(start: UnsafeRawPointer(self).advanced(by: MemoryLayout<segment_command_64>.size).assumingMemoryBound(to: section_64.self),
                            count: Int(self.pointee.nsects))
    }

}
