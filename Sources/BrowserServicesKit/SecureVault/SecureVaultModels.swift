//
//  SecureVaultModels.swift
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

import Foundation

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
    public struct WebsiteAccount {

        public var id: Int64?
        public var title: String?
        public var username: String
        public var domain: String
        public let created: Date
        public let lastUpdated: Date

        public init(title: String? = nil, username: String, domain: String) {
            self.id = nil
            self.title = title
            self.username = username
            self.domain = domain
            self.created = Date()
            self.lastUpdated = self.created
        }

        init(id: Int64, title: String? = nil, username: String, domain: String, created: Date, lastUpdated: Date) {
            self.id = id
            self.title = title
            self.username = username
            self.domain = domain
            self.created = created
            self.lastUpdated = lastUpdated
        }

    }

    public struct CreditCard {

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
        
        public init?(dictionary: [String: Any]) {
            guard let cardNumber = dictionary["cardNumber"] as? String else {
                return nil
            }

            self.init(id: nil,
                      title: nil,
                      cardNumber: cardNumber,
                      cardholderName: dictionary["cardholderName"] as? String,
                      cardSecurityCode: dictionary["cardSecurityCode"] as? String,
                      expirationMonth: dictionary["expirationMonth"] as? Int,
                      expirationYear: dictionary["expirationYear"] as? Int)
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

            // The title's empty, so assume that the first non-empty line is used as the title, and find the second non-
            // empty line instead.
            
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

        private static let personNameComponentsFormatter: PersonNameComponentsFormatter = {
            let nameFormatter = PersonNameComponentsFormatter()
            nameFormatter.style = .medium

            return nameFormatter
        }()
        
        public var formattedName: String {
            var nameComponents = PersonNameComponents()
            nameComponents.givenName = firstName
            nameComponents.middleName = middleName
            nameComponents.familyName = lastName

            return Self.personNameComponentsFormatter.string(from: nameComponents)
        }
        
        private(set) var autofillEqualityName: String?
        private(set) var autofillEqualityAddressStreet: String?

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
        
        public init(dictionary: [String: Any]) {
            self.init(id: nil,
                      title: nil,
                      created: Date(),
                      lastUpdated: Date(),
                      firstName: dictionary["firstName"] as? String,
                      middleName: dictionary["middleName"] as? String,
                      lastName: dictionary["lastName"] as? String,
                      birthdayDay: dictionary["birthdayDay"] as? Int,
                      birthdayMonth: dictionary["birthdayMonth"] as? Int,
                      birthdayYear: dictionary["birthdayYear"] as? Int,
                      addressStreet: dictionary["addressStreet"] as? String,
                      addressStreet2: dictionary["addressStreet2"] as? String,
                      addressCity: dictionary["addressCity"] as? String,
                      addressProvince: dictionary["addressProvince"] as? String,
                      addressPostalCode: dictionary["addressPostalCode"] as? String,
                      addressCountryCode: dictionary["addressCountryCode"] as? String,
                      homePhone: dictionary["homePhone"] as? String,
                      mobilePhone: dictionary["mobilePhone"] as? String,
                      emailAddress: dictionary["emailAddress"] as? String)
        }
        
        private func normalizedAutofillName() -> String {
            let nameString = (firstName ?? "") + (middleName ?? "") + (lastName ?? "")
            return nameString.autofillNormalized()
        }

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
        if self.cardNumber == object.cardNumber {
            return true
        }
        
        return false
    }
    
}
