//
//  File.swift
//  
//
//  Created by Alexey Martemianov on 20.12.2022.
//

import Foundation

extension URL {
    public static let empty = (NSURL(string: "") ?? NSURL()) as URL

    public var isEmpty: Bool {
        absoluteString.isEmpty
    }
}
