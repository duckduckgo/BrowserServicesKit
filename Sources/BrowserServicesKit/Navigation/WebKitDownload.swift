//
//  File.swift
//  
//
//  Created by Alexey Martemianov on 05.12.2022.
//

import WebKit

public protocol WebKitDownload: NSObject {
    var originalRequest: URLRequest? { get }
    var webView: WKWebView? { get }
}

extension WebKitDownload {
    public func cancel(_ completionHandler: ((Data?) -> Void)?) {
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
