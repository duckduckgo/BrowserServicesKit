//
//  segment_command+segname.swift
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

    struct Sections: Sequence {
        let segment: UnsafePointer<segment_command_64>

        struct SectionIterator: IteratorProtocol {
            var current: UnsafeRawPointer
            var count: UInt32

            init(segment: UnsafePointer<segment_command_64>) {
                self.current = UnsafeRawPointer(segment).advanced(by: MemoryLayout<segment_command_64>.size)
                self.count = segment.pointee.nsects
            }

            mutating func next() -> UnsafePointer<section_64>? {
                guard count > 0 else { return nil }

                let section = current.bindMemory(to: section_64.self, capacity: 1)
                current = current.advanced(by: MemoryLayout<section_64>.size)
                count -= 1

                return section
            }
        }

        func makeIterator() -> SectionIterator {
            SectionIterator(segment: segment)
        }
    }

    var sections: Sections {
        return Sections(segment: self)
    }

}
