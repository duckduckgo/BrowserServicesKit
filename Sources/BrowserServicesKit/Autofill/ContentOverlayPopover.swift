//
//  ContentOverlayPopover.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Cocoa
import WebKit

public final class ContentOverlayPopover: NSPopover {
    
    public var zoomFactor: CGFloat?
    public var webView: WKWebView?

    public override init() {
        super.init()
        animates = false
        appearance = NSAppearance(named: NSAppearance.Name.vibrantLight)

#if DEBUG
        behavior = .semitransient
#else
        behavior = .transient
#endif

        setupContentController()
    }

    public required init?(coder: NSCoder) {
        fatalError("ContentOverlayPopover: Bad initializer")
    }
    
    // swiftlint:disable force_cast
    public var viewController: ContentOverlayViewController { contentViewController as! ContentOverlayViewController }
    // swiftlint:enable force_cast

    // swiftlint:disable force_cast
    private func setupContentController() {
        let storyboard = NSStoryboard(name: "ContentOverlay", bundle: Bundle.module)
        let controller = storyboard
            .instantiateController(withIdentifier: "ContentOverlayViewController") as! ContentOverlayViewController
        contentViewController = controller
    }
    // swiftlint:enable force_cast
    
    
    public func setTypes(inputType: String) {
        let c = contentViewController as! ContentOverlayViewController
        c.zoomFactor = zoomFactor
        c.inputType = inputType
    }
    
    public func display(rect: NSRect, of: NSView, width: CGFloat) {
        guard let insetBy = self.value(forKeyPath: "anchorSize")! as? CGSize else {
            return
        }
        // Inset the rectangle by the anchor size as setting the anchorSize to 0 seems impossible
        self.show(relativeTo: rect.insetBy(dx: insetBy.width, dy: insetBy.height), of: of, preferredEdge: .minY)
        self.contentSize = NSSize.init(width: width, height: 200)
    }
}
