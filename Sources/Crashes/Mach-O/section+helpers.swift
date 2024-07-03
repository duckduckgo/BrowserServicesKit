//
//  section+helpers.swift
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

import Foundation

extension section_64 {

    var type: Int32 {
        Int32(self.flags) & SECTION_TYPE
    }

    var count: Int {
        Int(self.size / UInt64(MemoryLayout<UnsafeMutableRawPointer?>.size))
    }

    func indirectSymbolIndices(indirectSymtab: UnsafePointer<UInt32>) -> UnsafeBufferPointer<UInt32> {
        UnsafeBufferPointer(start: indirectSymtab.advanced(by: Int(self.reserved1)), count: self.count)
    }

    func indirectSymbolBindings(slide: Int) -> UnsafeBufferPointer<UnsafeRawPointer> {
        UnsafeRawBufferPointer(start: UnsafeRawPointer(bitPattern: UInt(self.addr))!.advanced(by: slide),
                               count: Int(self.size)).assumingMemoryBound(to: UnsafeRawPointer.self)
    }

}
