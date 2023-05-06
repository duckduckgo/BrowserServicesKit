//
//  SecureVaultModels.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");zº
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
import Common

/// The models used by the secure vault.
/// 
/// Future models include:
///  * Generated Password - a password generated for a site, but not used yet
///  * Duck Address - a duck address used on a partcular site
public struct SecureVaultModels {

    /// A username and password was saved for a given site.  Password is stored seperately so that
    ///  it can be queried independently.
    public struct WebsiteCredentials {

        public var account: WebsiteAccount
        public var password: Data

        public init(account: WebsiteAccount, password: Data) {
            self.account = account
            self.password = password
        }

    }

    /// The username associated with a domain.
    public struct WebsiteAccount: Equatable {

        public var id: String?
        public var title: String?
        public var username: String
        public var domain: String
        public var signature: String?
        public var notes: String?
        public let created: Date
        public let lastUpdated: Date        

        public init(title: String? = nil, username: String, domain: String, signature: String? = nil, notes: String? = nil) {
            self.id = nil
            self.title = title
            self.username = username
            self.domain = domain
            self.signature = signature
            self.notes = notes
            self.created = Date()
            self.lastUpdated = self.created
        }

        public init(id: String, title: String? = nil, username: String, domain: String, signature: String? = nil, notes: String? = nil, created: Date, lastUpdated: Date) {
            self.id = id
            self.title = title
            self.username = username
            self.domain = domain
            self.signature = signature
            self.notes = notes
            self.created = created
            self.lastUpdated = lastUpdated
        }
        
        private var tld: String {
            let components = self.domain.split(separator: ".")
            if components.count >= 2 {
            let tldIndex = components.count - 2
            let baseTLD = components[tldIndex]
                return String(baseTLD)
            }
            return ""
        }
        
        // djb2 hash from the account
        var hashValue: Data {
            var hash = 5381
            for char in "\(username)\(tld)".utf8 {
                hash = ((hash << 5) &+ hash) &+ Int(char)
            }
            let hashString = String(format: "%02x", hash)
            guard let hash = hashString.data(using: .utf8) else {
                return Data()
            }
            return hash
        }

    }

    public struct CreditCard {

        private enum Constants {
            static let creditCardsKey = "creditCards"
            static let cardNumberKey = "cardNumber"
            static let cardNameKey = "cardName"
            static let cardSecurityCodeKey = "cardSecurityCode"
            static let expirationMonthKey = "expirationMonth"
            static let expirationYearKey = "expirationYear"
        }
        
        public var id: Int64?
        public var title: String
        public let created: Date
        public let lastUpdated: Date

        public var cardNumberData: Data
        public var cardSuffix: String // Stored as L1 data, used when presenting a list of cards in the Autofill UI
        public var cardholderName: String?
        public var cardSecurityCode: String?
        public var expirationMonth: Int?
        public var expirationYear: Int?
        
        public var cardNumber: String {
            return String(data: cardNumberData, encoding: .utf8)!
        }

        public var displayName: String {
            let type = CreditCardValidation.type(for: cardNumber)
            return "\(type.displayName) (\(cardSuffix))"
        }
        
        static func suffix(from cardNumber: String) -> String {
            let trimmedCardNumber = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmedCardNumber.suffix(4))
        }

        public init(id: Int64? = nil,
                    title: String? = nil,
                    cardNumber: String,
                    cardholderName: String?,
                    cardSecurityCode: String?,
                    expirationMonth: Int?,
                    expirationYear: Int?) {
            self.id = id
            self.title = title ?? ""
            self.created = Date()
            self.lastUpdated = self.created

            self.cardNumberData = cardNumber.data(using: .utf8)!
            self.cardSuffix = Self.suffix(from: cardNumber)
            self.cardholderName = cardholderName
            self.cardSecurityCode = cardSecurityCode
            self.expirationMonth = expirationMonth
            self.expirationYear = expirationYear
        }
        
        public init?(autofillDictionary: [String: Any]) {
            guard let creditCardsDictionary = autofillDictionary[Constants.creditCardsKey] as? [String: Any] else {
                return nil
            }
            
            self.init(creditCardsDictionary: creditCardsDictionary)
        }
        
        public init?(creditCardsDictionary: [String: Any]) {
            guard let cardNumber = creditCardsDictionary[Constants.cardNumberKey] as? String else {
                return nil
            }

            self.init(id: nil,
                      title: nil,
                      cardNumber: cardNumber,
                      cardholderName: creditCardsDictionary[Constants.cardNameKey] as? String,
                      cardSecurityCode: creditCardsDictionary[Constants.cardSecurityCodeKey] as? String,
                      expirationMonth: Int(creditCardsDictionary[Constants.expirationMonthKey] as? String ?? ""),
                      expirationYear: Int(creditCardsDictionary[Constants.expirationYearKey] as? String ?? ""))
        }

    }

    public struct Note {

        public var id: Int64?
        public var title: String
        public let created: Date
        public let lastUpdated: Date

        public var associatedDomain: String?
        public var text: String {
            didSet {
                self.displayTitle = generateDisplayTitle()
                self.displaySubtitle = generateDisplaySubtitle()
            }
        }

        public init(title: String? = nil, associatedDomain: String? = nil, text: String) {
            self.id = nil
            self.title = title ?? ""
            self.created = Date()
            self.lastUpdated = self.created

            self.associatedDomain = associatedDomain
            self.text = text
            
            self.displayTitle = generateDisplayTitle()
            self.displaySubtitle = generateDisplaySubtitle()
        }
        
        // Display Properties:
        
        public internal(set) var displayTitle: String?
        public internal(set) var displaySubtitle: String = ""
        
        /// If a note has a title, it will be used when displaying the note in the UI. If it doesn't have a title and it has body text, the first non-empty line of the body text
        /// will be used. If it doesn't have a title or body text, a placeholder string is used.
        internal func generateDisplayTitle() -> String? {
            guard title.isEmpty else {
                return title
            }

            // If a note doesn't have a title, the first non-empty line will be used instead.
            let noteLines = text.components(separatedBy: .newlines)
            return noteLines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
        
        /// If a note has a title, the first non-empty line of the note is used as the subtitle. If it doesn't have a title, the first non-empty line will be used as a title, so the
        /// second non-empty line will then be used as the subtitle. If there is no title or body text, an empty string is returned.
        internal func generateDisplaySubtitle() -> String {
            guard title.isEmpty else {
                return firstNonEmptyLine ?? ""
            }

            // The title is empty, so assume that the first non-empty line is used as the title, and find the second non-empty line instead.
            let noteLines = text.components(separatedBy: .newlines)
            var alreadyFoundFirstNonEmptyLine = false
            
            for line in noteLines where !line.isEmpty {
                if !alreadyFoundFirstNonEmptyLine {
                    alreadyFoundFirstNonEmptyLine = true
                } else if alreadyFoundFirstNonEmptyLine {
                    return line
                }
            }
            
            return ""
        }
        
        private var firstNonEmptyLine: String? {
            let noteLines = text.components(separatedBy: .newlines)
            return noteLines.first(where: { !$0.isEmpty })
        }

    }

    public struct Identity {

        private static let mediumPersonNameComponentsFormatter: PersonNameComponentsFormatter = {
            let nameFormatter = PersonNameComponentsFormatter()
            nameFormatter.style = .medium
            return nameFormatter
        }()
        
        private static let longPersonNameComponentsFormatter: PersonNameComponentsFormatter = {
            let nameFormatter = PersonNameComponentsFormatter()
            nameFormatter.style = .long
            return nameFormatter
        }()
        
        private var nameComponents: PersonNameComponents {
            var nameComponents = PersonNameComponents()

            nameComponents.givenName = firstName
            nameComponents.middleName = middleName
            nameComponents.familyName = lastName

            return nameComponents
        }
        
        public var formattedName: String {
            return Self.mediumPersonNameComponentsFormatter.string(from: nameComponents)
        }
        
        public var longFormattedName: String {
            return Self.longPersonNameComponentsFormatter.string(from: nameComponents)
        }
        
        var autofillEqualityName: String?
        var autofillEqualityAddressStreet: String?

        public var id: Int64?
        public var title: String
        public let created: Date
        public let lastUpdated: Date

        public var firstName: String? {
            didSet {
                autofillEqualityName = normalizedAutofillName()
            }
        }

        public var middleName: String? {
            didSet {
                autofillEqualityName = normalizedAutofillName()
            }
        }

        public var lastName: String? {
            didSet {
                autofillEqualityName = normalizedAutofillName()
            }
        }

        public var birthdayDay: Int?
        public var birthdayMonth: Int?
        public var birthdayYear: Int?

        public var addressStreet: String? {
            didSet {
                autofillEqualityAddressStreet = addressStreet?.autofillNormalized()
            }
        }

        public var addressStreet2: String?
        public var addressCity: String?
        public var addressProvince: String?
        public var addressPostalCode: String?

        /// ISO country code, e.g. `CA`
        public var addressCountryCode: String?

        public var homePhone: String?
        public var mobilePhone: String?
        public var emailAddress: String?

        public init() {
            self.init(id: nil, title: "", created: Date(), lastUpdated: Date())
        }

        public init(id: Int64? = nil,
                    title: String? = nil,
                    created: Date,
                    lastUpdated: Date,
                    firstName: String? = nil,
                    middleName: String? = nil,
                    lastName: String? = nil,
                    birthdayDay: Int? = nil,
                    birthdayMonth: Int? = nil,
                    birthdayYear: Int? = nil,
                    addressStreet: String? = nil,
                    addressStreet2: String? = nil,
                    addressCity: String? = nil,
                    addressProvince: String? = nil,
                    addressPostalCode: String? = nil,
                    addressCountryCode: String? = nil,
                    homePhone: String? = nil,
                    mobilePhone: String? = nil,
                    emailAddress: String? = nil) {
            self.id = id
            self.title = title ?? ""
            self.created = created
            self.lastUpdated = lastUpdated
            self.firstName = firstName
            self.middleName = middleName
            self.lastName = lastName
            self.birthdayDay = birthdayDay
            self.birthdayMonth = birthdayMonth
            self.birthdayYear = birthdayYear
            self.addressStreet = addressStreet
            self.addressStreet2 = addressStreet2
            self.addressCity = addressCity
            self.addressProvince = addressProvince
            self.addressPostalCode = addressPostalCode
            self.addressCountryCode = addressCountryCode
            self.homePhone = homePhone
            self.mobilePhone = mobilePhone
            self.emailAddress = emailAddress
            
            self.autofillEqualityName = normalizedAutofillName()
            self.autofillEqualityAddressStreet = addressStreet?.autofillNormalized()
        }
        
        public init?(autofillDictionary: [String: Any]) {
            guard let dictionary = autofillDictionary["identities"] as? [String: Any] else {
                return nil
            }
            
            self.init(identityDictionary: dictionary)
        }

        public init(identityDictionary: [String: Any]) {
            self.init(id: nil,
                      title: nil,
                      created: Date(),
                      lastUpdated: Date(),
                      firstName: identityDictionary["firstName"] as? String,
                      middleName: identityDictionary["middleName"] as? String,
                      lastName: identityDictionary["lastName"] as? String,
                      birthdayDay: identityDictionary["birthdayDay"] as? Int,
                      birthdayMonth: identityDictionary["birthdayMonth"] as? Int,
                      birthdayYear: identityDictionary["birthdayYear"] as? Int,
                      addressStreet: identityDictionary["addressStreet"] as? String,
                      addressStreet2: identityDictionary["addressStreet2"] as? String,
                      addressCity: identityDictionary["addressCity"] as? String,
                      addressProvince: identityDictionary["addressProvince"] as? String,
                      addressPostalCode: identityDictionary["addressPostalCode"] as? String,
                      addressCountryCode: identityDictionary["addressCountryCode"] as? String,
                      homePhone: identityDictionary["phone"] as? String,
                      mobilePhone: nil,
                      emailAddress: identityDictionary["emailAddress"] as? String)
        }

        func normalizedAutofillName() -> String {
            let nameString = (firstName ?? "") + (middleName ?? "") + (lastName ?? "")
            return nameString.autofillNormalized()
        }

    }

    public struct CredentialsProvider {

        public enum Name: String {
            case duckduckgo
            case bitwarden
        }

        public var name: Name
        public var locked: Bool

    }

}

// MARK: - Autofill Equality

protocol SecureVaultAutofillEquatable {
    
    func hasAutofillEquality(comparedTo object: Self) -> Bool
    
}

extension SecureVaultModels.Identity: SecureVaultAutofillEquatable {

    func hasAutofillEquality(comparedTo otherIdentity: SecureVaultModels.Identity) -> Bool {
        let hasNameEquality = self.autofillEqualityName == otherIdentity.autofillEqualityName
        let hasAddressEquality = self.autofillEqualityAddressStreet == otherIdentity.autofillEqualityAddressStreet
        
        return hasNameEquality && hasAddressEquality
    }
    
}

extension SecureVaultModels.CreditCard: SecureVaultAutofillEquatable {
    
    func hasAutofillEquality(comparedTo object: Self) -> Bool {
        if self.cardNumber.autofillNormalized() == object.cardNumber.autofillNormalized() {
            return true
        }
        
        return false
    }
    
}

// MARK: - WebsiteAccount Array extensions
extension Array where Element == SecureVaultModels.WebsiteAccount {

    private func extractTLD(domain: String, tld: TLD) -> String? {
        var urlComponents = URLComponents()
        urlComponents.host = domain
        return urlComponents.eTLDplus1(tld: tld)
    }

    func dedupedAndSortedForDomain(_ targetDomain: String, tld: TLD) -> [SecureVaultModels.WebsiteAccount] {
        return removingDuplicatesForDomain(targetDomain, tld: tld).sortedForDomain(targetDomain, tld: tld)
    }

    // Last Updated > Alphabetical Domain > Alphabetical Username > Empty Usernames
    private func compareAccount(_ account1: SecureVaultModels.WebsiteAccount, _ account2: SecureVaultModels.WebsiteAccount) -> Bool {
        return !account1.username.isEmpty &&
        account1.lastUpdated > account2.lastUpdated &&
        account1.domain < account2.domain &&
        account1.username < account2.username
    }

    func sortedForDomain(_ targetDomain: String, tld: TLD) -> [SecureVaultModels.WebsiteAccount] {

        // Sorts accounts for autofill suggestions
        // First: Exact matches to provided URL
        // Second: Accounts matching TLD (www subdomain accounts are considered a TLD match)
        // Third: Other accounts, sorted by lastUpdated > Alphabetically
        guard let targetTLD = extractTLD(domain: targetDomain, tld: tld) else {
            return []
        }
        let sortedAccounts = self.sorted { account1, account2 in
            let domain1 = account1.domain
            let domain2 = account2.domain

            let tld1 = extractTLD(domain: domain1, tld: tld)
            let tld2 = extractTLD(domain: domain2, tld: tld)

            // Exact match sorting
            if domain1 == targetDomain {
                return compareAccount(account1, account2)
            } else if domain2 == targetDomain {
                return compareAccount(account2, account1)
            }

            // Prioritize TLD over other subdomains
            if tld1 == targetTLD && tld2 == targetTLD {

                // We treat WWW subdomains as TLD
                let d1 = domain1.hasPrefix("www") ? extractTLD(domain: domain1, tld: tld) : domain1
                let d2 = domain2.hasPrefix("www") ? extractTLD(domain: domain2, tld: tld) : domain2

                if d1 == targetTLD {
                    return compareAccount(account1, account2)
                } else if d2 == targetTLD {
                    return compareAccount(account2, account1)
                }
            }

            // Remaining stuff sorted by lastUpdated > Alphabetically            
            if account1.lastUpdated == account2.lastUpdated {
                return domain1 < domain2
            } else {
                return account1.lastUpdated > account2.lastUpdated
            }

        }
        return sortedAccounts
    }

    // Dedupes Accounts based on specific conditions
    // A. Remove all except the exact match to the provided domain (if available) OR
    // B. Remove all except for a matching TLD domain (if available)
    // C. Remove all except the most recently updated account
    func removingDuplicatesForDomain(_ targetDomain: String, tld: TLD) -> [SecureVaultModels.WebsiteAccount] {
        var urlComponents = URLComponents()
        urlComponents.host = targetDomain

        var uniqueAccounts = [String: SecureVaultModels.WebsiteAccount]()

        self.forEach { account in
            guard let signature = account.signature else {
                return
            }

            guard let existingAccount = uniqueAccounts[signature] else {
                uniqueAccounts[signature] = account
                return
            }

            let isTLD = account.domain == urlComponents.eTLDplus1(tld: tld)
            let isExactMatch = account.domain == targetDomain
            let isNewer = existingAccount.domain != targetDomain && account.lastUpdated > existingAccount.lastUpdated

            let existingIsExactMatch = existingAccount.domain == targetDomain
            let existingIsTLD = existingAccount.domain == urlComponents.eTLDplus1(tld: tld)

            if isExactMatch {
                uniqueAccounts[signature] = account
            } else if !existingIsExactMatch && (isTLD || isNewer) {
                uniqueAccounts[signature] = account
            } else if !existingIsExactMatch && !existingIsTLD && isNewer {
                uniqueAccounts[signature] = account
            }

        }

        return Array(uniqueAccounts.values)
    }

}
