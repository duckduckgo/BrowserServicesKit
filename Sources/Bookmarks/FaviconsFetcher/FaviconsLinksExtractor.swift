//
//  FaviconsLinksExtractor.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct FaviconLink {
    public let href: String
    public let rel: String
}

class FaviconsLinksExtractor: NSObject, XMLParserDelegate {

    let data: Data
    let baseURL: URL
    var links: [FaviconLink] = []
    private var isStopExpected = false

    static let matchingRelAttributes: Set<String> = ["icon", "favicon", "apple-touch-icon"]

    init(data: Data, baseURL: URL) {
        self.data = data
        self.baseURL = baseURL
    }

    func extractLinks() -> [FaviconLink] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        links.removeAll()
        parser.parse()
        if !isStopExpected {
            assert(parser.parserError == nil)
        }
        return links
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print(parseError)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "head":
            isInsideHead = true
        case "link":
            if isInsideHead {
                if let rel = attributeDict["rel"] {
                    if rel.lowercased() == "apple-touch-icon" || rel.lowercased() == "favicon" || rel.lowercased().contains("icon") {
//                    if Self.matchingRelAttributes.contains(where: { rel.localizedCaseInsensitiveContains($0) }) {
//                        print("rel \(rel)")
                        if let href = attributeDict["href"],
                           !href.localizedCaseInsensitiveContains("svg") && attributeDict["type"]?.localizedCaseInsensitiveContains("svg") != true {
                            print("found \(rel) \(href)")
                            links.append(.init(href: absoluteURLString(for: href), rel: rel))
                        }
                    }
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "head" {
            isStopExpected = true
            parser.abortParsing()
        }
    }

    private func absoluteURLString(for extractedHref: String) -> String {
        var href = extractedHref
        if var components = URLComponents(string: href) {
            var updated = false
            if components.host == nil {
                components.host = baseURL.host
                updated = true
            }
            if components.scheme == nil {
                components.scheme = "https" // links.documentURL.scheme
                updated = true
            }
            if updated, let url = components.url {
                href = url.absoluteString
            }
        }
        return href
    }

    private var isInsideHead = false
}
