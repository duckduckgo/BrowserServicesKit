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

struct FaviconLink {
    let href: String
    let rel: String
}

class FaviconsLinksExtractor: NSObject, XMLParserDelegate {

    let data: Data
    var links: [FaviconLink] = []

    static let matchingRelAttributes: Set<String> = ["icon", "favicon", "apple-touch-icon"]

    init(data: Data) {
        self.data = data
    }

    func extractLinks() -> [FaviconLink] {
        let parser = XMLParser(data: data)
        links.removeAll()
        parser.parse()
        return links
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case "head":
            isInsideHead = true
        case "link":
            if let rel = attributeDict["rel"], Self.matchingRelAttributes.contains(rel),
               let href = attributeDict["href"],
                !href.localizedCaseInsensitiveContains("svg") && attributeDict["type"]?.localizedCaseInsensitiveContains("svg") != true
            {
                links.append(.init(href: href, rel: rel))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "head" {
            parser.abortParsing()
        }
    }

    private var isInsideHead = false
}
