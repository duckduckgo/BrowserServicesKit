//
//  AMPProtection.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import WebKit

public struct AMPProtection {
    
    private let linkCleaner: LinkCleaner
    private let ampExtractor: AMPCanonicalExtractor
    
    public init(privacyManager: PrivacyConfigurationManager, contentBlockingManager: ContentBlockerRulesManager, errorReporting: EventMapping<AMPProtectionDebugEvents>) {
        linkCleaner = LinkCleaner(privacyManager: privacyManager)
        ampExtractor = AMPCanonicalExtractor(linkCleaner: linkCleaner,
                                             privacyManager: privacyManager,
                                             contentBlockingManager: contentBlockingManager,
                                             errorReporting: errorReporting)
    }
    
    public func getCleanURL(from url: URL, onExtracting: () -> Void, completion: @escaping (URL) -> Void) {
        var urlToLoad = url
        if let cleanURL = linkCleaner.cleanTrackingParameters(initiator: nil, url: urlToLoad) {
            urlToLoad = cleanURL
        }
        
        if let cleanURL = linkCleaner.extractCanonicalFromAMPLink(initiator: nil, destination: urlToLoad) {
            completion(cleanURL)
        } else if ampExtractor.urlContainsAMPKeyword(urlToLoad) {
            onExtracting()
            ampExtractor.getCanonicalURL(initiator: nil, url: urlToLoad) { canonical in
                if let canonical = canonical {
                    completion(canonical)
                } else {
                    completion(urlToLoad)
                }
            }
        } else {
            completion(urlToLoad)
        }
    }
    
    public func getCleanURL(from url: URL, onExtracting: () -> Void) async -> URL {
        await withCheckedContinuation { continuation in
            getCleanURL(from: url, onExtracting: onExtracting) { url in
                continuation.resume(returning: url)
            }
        }
    }
    
    public func requestTrackingLinkRewrite(initiatingURL: URL?,
                                           navigationAction: WKNavigationAction,
                                           onExtracting: () -> Void,
                                           onLinkRewrite: @escaping (URL, WKNavigationAction) -> Void,
                                           policyDecisionHandler: @escaping (WKNavigationActionPolicy) -> Void) -> Bool {
        let destinationURL = navigationAction.request.url
        
        var didRewriteLink = false
        if let newURL = linkCleaner.extractCanonicalFromAMPLink(initiator: initiatingURL, destination: destinationURL) {
            policyDecisionHandler(.cancel)
            onLinkRewrite(newURL, navigationAction)
            didRewriteLink = true
        } else if ampExtractor.urlContainsAMPKeyword(destinationURL) {
            onExtracting()
            ampExtractor.getCanonicalURL(initiator: initiatingURL, url: destinationURL) { canonical in
                guard let canonical = canonical, canonical != destinationURL else {
                    policyDecisionHandler(.allow)
                    return
                }
                
                policyDecisionHandler(.cancel)
                onLinkRewrite(canonical, navigationAction)
            }
            didRewriteLink = true
        } else if let newURL = linkCleaner.cleanTrackingParameters(initiator: initiatingURL, url: destinationURL) {
            if newURL != destinationURL {
                policyDecisionHandler(.cancel)
                onLinkRewrite(newURL, navigationAction)
                didRewriteLink = true
            }
        }
        
        return didRewriteLink
    }
    
    
    public func requestTrackingLinkRewrite(initiatingURL: URL?,
                                           navigationAction: WKNavigationAction,
                                           onExtracting: () -> Void,
                                           onLinkRewrite: @escaping (URL, WKNavigationAction) -> Void) async -> WKNavigationActionPolicy? {
        await withCheckedContinuation { continuation in
            let didRewriteLink = requestTrackingLinkRewrite(initiatingURL: initiatingURL,
                                                            navigationAction: navigationAction,
                                                            onExtracting: onExtracting,
                                                            onLinkRewrite: onLinkRewrite) { navigationActionPolicy in
                continuation.resume(returning: navigationActionPolicy)
            }
            
            if !didRewriteLink {
                continuation.resume(returning: nil)
            }
        }
    }
    
    public func cancelOngoingExtraction() { ampExtractor.cancelOngoingExtraction() }
    
    public var lastAMPURLString: String? { linkCleaner.lastAMPURLString }
    public var urlParametersRemoved: Bool { linkCleaner.urlParametersRemoved }
    
}
