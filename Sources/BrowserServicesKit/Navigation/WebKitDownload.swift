//
//  File.swift
//  
//
//  Created by Alexey Martemianov on 05.12.2022.
//

import WebKit

@objc public protocol WebKitDownload: AnyObject, NSObjectProtocol {
    var originalRequest: URLRequest? { get }
    var webView: WKWebView? { get }
    var delegate: WKDownloadDelegate? { get set }
}

extension WebKitDownload {
    public func cancel(_ completionHandler: ((Data?) -> Void)? = nil) {
        if #available(macOS 11.3, iOS 14.5, *) {
            if let download = self as? WKDownload {
                download.cancel(completionHandler)
            }
        } else {
            self.perform(#selector(Progress.cancel))
            completionHandler?(nil)
        }
    }
}

@available(macOS 11.3, iOS 14.5, *)
extension WKDownload: WebKitDownload {}
