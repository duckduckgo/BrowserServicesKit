//
//  File.swift
//  
//
//  Created by admin on 03.07.2024.
//

import Foundation

extension UnsafePointer where Pointee == section_64 {

    var type: Int32 {
        Int32(self.pointee.flags) & SECTION_TYPE
    }

    var count: Int {
        Int(self.pointee.size / UInt64(MemoryLayout<UnsafeMutableRawPointer?>.size))
    }

    func indirectSymbolIndices(indirectSymtab: UnsafePointer<UInt32>) -> UnsafeBufferPointer<UInt32> {
        UnsafeBufferPointer(start: indirectSymtab.advanced(by: Int(self.pointee.reserved1)), count: self.count)
    }

    func indirectSymbolBindings(slide: Int) -> UnsafeBufferPointer<UnsafeRawPointer> {
        UnsafeRawBufferPointer(start: UnsafeRawPointer(bitPattern: UInt(self.pointee.addr))!.advanced(by: slide),
                               count: Int(self.pointee.size)).assumingMemoryBound(to: UnsafeRawPointer.self)
    }

}
