//
//  CxaThrowSwapper.swift
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
//
// Inspired by kstenerud/KSCrash
// https://github.com/kstenerud/KSCrash
//
//  Copyright (c) 2019 YANDEX LLC. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
//
// Inspired by facebook/fishhook
// https://github.com/facebook/fishhook
//
// Copyright (c) 2013, Facebook, Inc.
// All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//   * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//   * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//   * Neither the name Facebook nor the names of its contributors may be used to
//     endorse or promote products derived from this software without specific
//     prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation
import Common
import MachO

public typealias CxaThrowType = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) -> Void

public struct CxaThrowSwapper {

    public static var log: OSLog = .disabled

    fileprivate static var cxaThrowHandler: CxaThrowType?
    /// Swap C++ `throw` to collect stack trace when throw happens
    public static func swapCxaThrow(with handler: CxaThrowType) {
        dispatchPrecondition(condition: .onQueue(.main))
        if cxaThrowHandler == nil {
            // iterate through mach headers loaded in memory and hook `__cxa_throw` method by overwriting its address.
            // when this function is first registered it is called for once for each image that is currently part of the process.
            _dyld_register_func_for_add_image(processMachHeader)
        }
        cxaThrowHandler = handler
    }

}

private enum ProcessingError: LocalizedError {
    case zeroSlide
    case imageMap

    var errorDescription: String? {
        switch self  {
        case .zeroSlide: "zero slide"
        case .imageMap: "could not load image map"
        }
    }
}

// _dyld_register_func_for_add_image callback
private func processMachHeader(_ header: UnsafePointer<mach_header>?, slide: Int) {
    do {
        try _processMachHeader(header.map(UnsafeRawPointer.init)?.assumingMemoryBound(to: mach_header_64.self), slide: slide)
    } catch {
        os_log(.error, log: CxaThrowSwapper.log, "mach header %s processing error: %s", header.debugDescription, error.localizedDescription)
    }
}

private var cxxOriginalThrowFunctions = [UnsafeRawPointer: UnsafeRawPointer]()
private let indicesToSkip = [UInt32(bitPattern: INDIRECT_SYMBOL_ABS), INDIRECT_SYMBOL_LOCAL, UInt32(Int64(INDIRECT_SYMBOL_LOCAL) | Int64(INDIRECT_SYMBOL_ABS))]

private func _processMachHeader(_ header: UnsafePointer<mach_header_64>?, slide: Int) throws {
    guard let header, slide != 0 else { throw ProcessingError.zeroSlide }
    let headerInfo = try Dl_info(header)
    os_log(.debug, log: CxaThrowSwapper.log, "processing image %s (%s), slide: %02X", String(cString: headerInfo.dli_fname), header.debugDescription, slide)

    guard let imageMap = ImageMap(header: header, slide: slide) else { throw ProcessingError.imageMap }

    for case .some(let segment) in [imageMap.dataSegment, imageMap.dataConstSegment] {
        for (sectionIdx, section) in segment.sections.enumerated() where [S_LAZY_SYMBOL_POINTERS, S_NON_LAZY_SYMBOL_POINTERS].contains(section.type) {
            let symtabIndices = section.indirectSymbolIndices(indirectSymtab: imageMap.indirectSymtab)
            for i in 0..<section.count {
                let symtabIndex = symtabIndices[i]
                guard !indicesToSkip.contains(symtabIndex) else { continue }
                let symbolName = imageMap.symbolName(at: Int(symtabIndex))
                guard symbolName == "___cxa_throw" else { continue }

                let sectionInfo = try Dl_info(segment.sections.baseAddress!.advanced(by: sectionIdx))
                try section.indirectSymbolBindings(slide: slide).withTemporaryUnprotectedMemory { indirectSymbolBindings in
                    os_log(.debug, log: CxaThrowSwapper.log, "found %s: %s", symbolName, indirectSymbolBindings[i].debugDescription)

                    cxxOriginalThrowFunctions[UnsafeRawPointer(sectionInfo.dli_fbase)] = indirectSymbolBindings[i]
                    indirectSymbolBindings[i] = unsafeBitCast(cxaThrowHandler as CxaThrowType, to: UnsafeRawPointer.self)
                }
                break
            }
        }
    }
}

// `std::__cxa_throw` hook
private func cxaThrowHandler(thrownException: UnsafeMutableRawPointer?, tinfo: UnsafeMutableRawPointer?, dest: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) {
    let kRequiredFrames = 2

    os_log(.debug, log: CxaThrowSwapper.log, "handling __cxa_throw")
    CxaThrowSwapper.cxaThrowHandler?(thrownException, tinfo, dest)

    var backtraceArr = [UnsafeMutableRawPointer?](repeating: nil, count: kRequiredFrames)
    let count = backtrace(&backtraceArr, Int32(kRequiredFrames))

    if count >= kRequiredFrames {
        var info = Dl_info()
        if dladdr(backtraceArr[kRequiredFrames - 1], &info) != 0 {
            if let function = cxxOriginalThrowFunctions[info.dli_fbase] {
                os_log(.debug, log: CxaThrowSwapper.log, "calling original __cxa_throw function at %p", function.debugDescription)
                let original = unsafeBitCast(function, to: CxaThrowType.self)
                original(thrownException, tinfo, dest)
            }
        }
    }
}
