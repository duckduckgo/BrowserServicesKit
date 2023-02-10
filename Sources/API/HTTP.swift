//
//  File.swift
//  
//
//  Created by Jacek Łyp on 09/02/2023.
//

import Foundation

public enum HTTPHeaderField {
    
    static let acceptEncoding = "Accept-Encoding"
    static let acceptLanguage = "Accept-Language"
    static let userAgent = "User-Agent"
    static let etag = "ETag"
    static let ifNoneMatch = "If-None-Match"
    static let moreInfo = "X-DuckDuckGo-MoreInfo"
    
}

public enum HTTPMethod: String {
    
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case connect = "CONNECT"
    case options = "OPTIONS"
    case trace = "TRACE"
    case patch = "PATCH"
    
}


