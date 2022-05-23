//
//  ContentScopePropertiesMocks.swift
//  
//
//  Created by Elle Sullivan on 23/05/2022.
//

import Foundation
@testable import BrowserServicesKit

extension ContentScopeFeatureToggles {
    static let allTogglesOn = ContentScopeFeatureToggles(emailProtection: true,
                                                         credentialsAutofill: true,
                                                         identitiesAutofill: true,
                                                         creditCardsAutofill: true,
                                                         credentialsSaving: true,
                                                         passwordGeneration: true)
}
