//
//  DaxDialogStyles.swift
//  DuckDuckGo
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

import SwiftUI

enum OnboardingStyles {}

extension OnboardingStyles {

    struct ListButtonStyle: ButtonStyle {
        @Environment(\.colorScheme) private var colorScheme

#if os(macOS)
        private let maxHeight = 32.0
#else
        private let maxHeight = 40.0
#endif

#if os(macOS)
        private let fontSize = 12.0
#else
        private let fontSize = 15.0
#endif

        init() {}

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: fontSize, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .foregroundColor(foregroundColor(configuration.isPressed))
                .padding()
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: maxHeight)
                .background(backgroundColor(configuration.isPressed))
                .cornerRadius(8)
                .contentShape(Rectangle()) // Makes whole button area tappable, when there's no background
        }

        private func foregroundColor(_ isPressed: Bool) -> Color {
            switch (colorScheme, isPressed) {
            case (.dark, false):
                return .blue30
            case (.dark, true):
                return .blue20
            case (_, false):
                return .blueBase
            case (_, true):
                return .blue70
            }
        }

        private func backgroundColor(_ isPressed: Bool) -> Color {
            switch (colorScheme, isPressed) {
            case (.light, true):
                return .blueBase.opacity(0.2)
            case (.dark, true):
                return .blue30.opacity(0.2)
            default:
                return .clear
            }
        }
    }

}

extension Color {
    static let blue70 = Color(0x1E42A4)
    static let blueBase = Color(0x3969EF)
    static let blue30 = Color(0x7295F6)
    static let blue20 = Color(0x8FABF9)

    init(_ hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
