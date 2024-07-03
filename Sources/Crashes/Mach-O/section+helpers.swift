//
//  File.swift
//  
//
//  Created by admin on 03.07.2024.
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
