//
//  ErrorPageHTMLTemplate.swift
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

import Foundation
import ContentScopeScripts
import WebKit
import Common

public struct ErrorPageHTMLTemplate {

    static var htmlTemplatePath: String {
        guard let file = ContentScopeScripts.Bundle.path(forResource: "index", ofType: "html", inDirectory: "pages/errorpage") else {
            assertionFailure("HTML template not found")
            return ""
        }
        return file
    }

    let error: WKError
    let header: String

    public init(error: WKError, header: String) {
        self.error = error
        self.header = header
    }

    public func makeHTMLFromTemplate() -> String {
        guard let html = try? String(contentsOfFile: Self.htmlTemplatePath) else {
            assertionFailure("Should be able to load template")
            return ""
        }
        return html.replacingOccurrences(of: "$ERROR_DESCRIPTION$", with: error.localizedDescription, options: .literal)
            .replacingOccurrences(of: "$HEADER$", with: header, options: .literal)
    }

}

public struct SSLErrorPageHTMLTemplate {
    let domain: String
    let errorCode: Int
    let tld = TLD()

    public init(domain: String, errorCode: Int) {
        self.domain = domain
        self.errorCode = errorCode
    }

    static var htmlTemplatePath: String {
        guard let file = ContentScopeScripts.Bundle.path(forResource: "index", ofType: "html", inDirectory: "pages/sslerrorpage") else {
            assertionFailure("HTML template not found")
            return ""
        }
        return file
    }

    public func makeHTMLFromTemplate() -> String {
        let sslError = SSLErrorType.forErrorCode(errorCode)
        guard let html = try? String(contentsOfFile: Self.htmlTemplatePath) else {
            assertionFailure("Should be able to load template")
            return ""
        }
        let eTldPlus1 = tld.eTLDplus1(domain) ?? domain
        let loadTimeData = createJSONString(header: sslError.header, body: sslError.body(for: domain), advancedButton: sslError.advancedButton, leaveSiteButton: sslError.leaveSiteButton, advancedInfoHeader: sslError.advancedInfoTitle, specificMessage: sslError.specificMessage(for: domain, eTldPlus1: eTldPlus1), advancedInfoBody: sslError.advancedInfoBody, visitSiteButton: sslError.visitSiteButton)
        return html.replacingOccurrences(of: "$LOAD_TIME_DATA$", with: loadTimeData, options: .literal)
    }

    private func createJSONString(header: String, body: String, advancedButton: String, leaveSiteButton: String, advancedInfoHeader: String, specificMessage: String, advancedInfoBody: String, visitSiteButton: String) -> String {
        let innerDictionary: [String: Any] = [
            "header": header,
            "body": body,
            "advancedButton": advancedButton,
            "leaveSiteButton": leaveSiteButton,
            "advancedInfoHeader": advancedInfoHeader,
            "specificMessage": specificMessage,
            "advancedInfoBody": advancedInfoBody,
            "visitSiteButton": visitSiteButton
        ]

        let outerDictionary: [String: Any] = [
            "strings": innerDictionary
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: outerDictionary, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            } else {
                return "Error: Could not encode jsonData to String."
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

}

public enum SSLErrorType {
    case expired
    case wrongHost
    case selfSigned
    case invalid

    var header: String {
        "Header"
//        return UserText.sslErrorPageHeader
    }

    func body(for domain: String) -> String {
        "Body for <span style=\"font-weight: 600;\">\(domain)</span>"
//        let boldDomain = "<span style=\"font-weight: 600;\">\(domain)</span>"
//        return UserText.sslErrorPageBody(boldDomain)
    }

    var advancedButton: String {
        "Advanced Button"
//        return UserText.sslErrorPageAdvancedButton
    }

    var leaveSiteButton: String {
        "Leave Site"
//        return UserText.sslErrorPageLeaveSiteButton
    }

    var visitSiteButton: String {
        "Visit Site"
//        return UserText.sslErrorPageVisitSiteButton
    }

    var advancedInfoTitle: String {
        "Advanced Info Title"
//        return UserText.sslErrorAdvancedInfoTitle
    }

    var advancedInfoBody: String {
        switch self {
        case .expired:
            return "sslErrorAdvancedInfoBodyExpired"
        case .wrongHost:
            return "sslErrorAdvancedInfoBodyWrongHost"
        case .selfSigned:
            return "sslErrorAdvancedInfoBodyWrongHost"
        case .invalid:
            return "sslErrorAdvancedInfoBodyWrongHost"
        }
    }

    func specificMessage(for domain: String, eTldPlus1: String) -> String {
        let boldDomain = "<span style=\"font-weight: 600;\">\(domain)</span>"
        let boldETldPlus1 = "<span style=\"font-weight: 600;\">\(eTldPlus1)</span>"
        switch self {
        case .expired:
            return "sslErrorCertificateExpiredMessage: \(boldDomain)"
        case .wrongHost:
            return "sslErrorCertificateWrongHostMessage: \(boldDomain), \(boldETldPlus1)"
        case .selfSigned:
            return "sslErrorCertificateSelfSignedMessage: \(boldDomain)"
        case .invalid:
            return "sslErrorCertificateSelfSignedMessage: \(boldDomain)"
        }
    }

    static func forErrorCode(_ errorCode: Int) -> Self {
        switch Int32(errorCode) {
        case errSSLCertExpired:
            return .expired
        case errSSLHostNameMismatch:
            return .wrongHost
        case errSSLXCertChainInvalid:
            return .selfSigned
        default:
            return .invalid
        }
    }

}
