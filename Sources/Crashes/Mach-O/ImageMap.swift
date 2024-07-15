//
//  ImageMap.swift
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
import MachO

struct ImageMap {

    let symtabCmd: symtab_command
    let dysymtabCmd: dysymtab_command

    let dataSegment: UnsafePointer<segment_command_64>?
    let dataConstSegment: UnsafePointer<segment_command_64>?

    let symtab: UnsafePointer<nlist_64>
    let strtab: UnsafePointer<Int8>
    // indirect symbol table (array of uint32_t indices into symbol table)
    let indirectSymtab: UnsafePointer<UInt32>

    init?(header: UnsafePointer<mach_header_64>, slide: Int) {
        guard case let (symtabCmd?, dysymtabCmd?, linkeditSegment?, dataSegment, dataConstSegment) = Self.findCommandsAndSegments(in: header) else { return nil }
        self.symtabCmd = symtabCmd
        self.dysymtabCmd = dysymtabCmd
        self.dataSegment = dataSegment
        self.dataConstSegment = dataConstSegment

        let linkeditBase = UnsafeRawPointer(bitPattern: UInt(linkeditSegment.vmaddr))!.advanced(by: slide - Int(linkeditSegment.fileoff))
        self.symtab = linkeditBase.advanced(by: Int(symtabCmd.symoff)).assumingMemoryBound(to: nlist_64.self)
        self.strtab = linkeditBase.advanced(by: Int(symtabCmd.stroff)).assumingMemoryBound(to: Int8.self)
        self.indirectSymtab = linkeditBase.advanced(by: Int(dysymtabCmd.indirectsymoff)).assumingMemoryBound(to: UInt32.self)
    }

    private typealias CommandsAndSegments = (symtabCmd: symtab_command?, dysymtabCmd: dysymtab_command?, linkeditSegment: segment_command_64?, dataSegment: UnsafePointer<segment_command_64>?, dataConstSegment: UnsafePointer<segment_command_64>?) // swiftlint:disable:this large_tuple

    private static func findCommandsAndSegments(in header: UnsafePointer<mach_header_64>) -> CommandsAndSegments {
        var result: CommandsAndSegments = (nil, nil, nil, nil, nil)

        for loadCommand in header.loadCommands {
            switch loadCommand.cmd {
            case LC_SYMTAB where result.symtabCmd == nil:
                result.symtabCmd = loadCommand.as(symtab_command.self).pointee
            case LC_DYSYMTAB where result.dysymtabCmd == nil:
                result.dysymtabCmd = loadCommand.as(dysymtab_command.self).pointee
            default:
                guard let segment = loadCommand.as(segment_command_64.self) else { continue }
                switch segment.segname {
                case SEG_LINKEDIT:
                    result.linkeditSegment = segment.pointee
                case SEG_DATA:
                    result.dataSegment = segment
                case "__DATA_CONST":
                    result.dataConstSegment = segment
                default: continue
                }
            }

            if result.symtabCmd != nil, result.dysymtabCmd != nil, result.linkeditSegment != nil, result.dataSegment != nil, result.dataConstSegment != nil {
                break
            }
        }

        return result
    }

    func symbolName(at symtabIndex: Int) -> String {
        let strtabOffset = symtab[symtabIndex].n_un.n_strx
        let symbolName = strtab.advanced(by: Int(strtabOffset))
        let symbolNameStr = String(cString: symbolName)

        return symbolNameStr
    }

}
