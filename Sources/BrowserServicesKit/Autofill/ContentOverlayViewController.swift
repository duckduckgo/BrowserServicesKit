//
//  ContentPopupViewController.swift
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
import Combine

@objc public protocol AutofillMessaging {
    func messageSelectedCredential(_ credential: String)
}

public final class ContentOverlayViewController: NSViewController, EmailManagerRequestDelegate {
    
    @IBOutlet var webView: WKWebView!
    private let topAutofillUserScript = TopAutofillUserScript()
    private var cancellables = Set<AnyCancellable>()
    @Published var pendingUpdates = Set<String>()
    public var zoomFactor: CGFloat?
    public var inputType: String?
    
    public var messageInterfaceBack: AutofillMessaging?
    
    lazy var emailManager: EmailManager = {
        let emailManager = EmailManager()
        emailManager.requestDelegate = self
        return emailManager
    }()
    
    lazy var vaultManager: SecureVaultManager = {
        let manager = SecureVaultManager()
        manager.delegate = self
        return manager
    }()
    
    public override func viewDidLoad() {
        // privacyDashboardScript.delegate = self
        initWebView()
        topAutofillUserScript.messageInterfaceBack = messageInterfaceBack
        topAutofillUserScript.emailDelegate = emailManager
        topAutofillUserScript.vaultDelegate = vaultManager
        print("view did load \(inputType)")
        // TODO I think this probably would race
        topAutofillUserScript.inputType = inputType

        webView.configuration.userContentController.addHandler(topAutofillUserScript)
        webView.configuration.userContentController.addUserScript(topAutofillUserScript.makeWKUserScript())
    }

    public override func viewWillAppear() {
        let url = Bundle.module.url(forResource: "TopAutofill", withExtension: "html")!
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    public override func viewWillDisappear() {
        cancellables.removeAll()
    }

    public func isPendingUpdates() -> Bool {
        return !pendingUpdates.isEmpty
    }

    private func initWebView() {
        let configuration = WKWebViewConfiguration()
        
#if DEBUG
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // webView.navigationDelegate = self
        self.webView = webView
        print("init webview:")
        if let zoomFactor = zoomFactor {
            print("zf: \(zoomFactor)")
            webView.magnification = zoomFactor
        }
        view.addAndLayout(webView)
    }

    // EmailManagerRequestDelegate

    // swiftlint:disable function_parameter_count
    public func emailManager(_ emailManager: EmailManager,
                      requested url: URL,
                      method: String,
                      headers: [String: String],
                      parameters: [String: String]?,
                      httpBody: Data?,
                      timeoutInterval: TimeInterval,
                      completion: @escaping (Data?, Error?) -> Void) {
        let currentQueue = OperationQueue.current

        let finalURL: URL

        if let parameters = parameters {
            finalURL = (try? url.addParameters(parameters)) ?? url
        } else {
            finalURL = url
        }

        var request = URLRequest(url: finalURL, timeoutInterval: timeoutInterval)
        request.allHTTPHeaderFields = headers
        request.httpMethod = method
        request.httpBody = httpBody
        URLSession.shared.dataTask(with: request) { (data, _, error) in
            currentQueue?.addOperation {
                completion(data, error)
            }
        }.resume()
    }
    // swiftlint:enable function_parameter_count
    
}

extension ContentOverlayViewController: SecureVaultManagerDelegate {

    public func secureVaultManager(_: SecureVaultManager, promptUserToStoreCredentials credentials: SecureVaultModels.WebsiteCredentials) {
        // TODO
        // delegate?.tab(self, requestedSaveCredentials: credentials)
    }

    public func secureVaultManager(_: SecureVaultManager, didAutofill type: AutofillType, withObjectId objectId: Int64) {
        // TODO
        // Pixel.fire(.formAutofilled(kind: type.formAutofillKind))
    }

}
