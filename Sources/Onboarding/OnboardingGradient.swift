//
//  OnboardingGradient.swift
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

public struct OnboardingGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    private let type: OnboardingGradientType

    public init(type: OnboardingGradientType) {
        self.type = type
    }

    public var body: some View {
        switch (type, colorScheme) {
        case (.default, .light):
            linearLightGradient
        case (.default, .dark):
            linearDarkGradient
        case (.highlights, .light):
            EllipticalLightGradient()
        case (.highlights, .dark):
            EllipticalDarkGradient()
        @unknown default:
            linearLightGradient
        }
    }

    private var linearLightGradient: some View {
        gradient(colorStops: [
            .init(color: Color(red: 1, green: 0.9, blue: 0.87), location: 0.00),
            .init(color: Color(red: 0.99, green: 0.89, blue: 0.87), location: 0.28),
            .init(color: Color(red: 0.99, green: 0.89, blue: 0.87), location: 0.46),
            .init(color: Color(red: 0.96, green: 0.87, blue: 0.87), location: 0.72),
            .init(color: Color(red: 0.9, green: 0.84, blue: 0.92), location: 1.00),
        ])
    }

    private var linearDarkGradient: some View {
        gradient(colorStops: [
            .init(color: Color(red: 0.29, green: 0.19, blue: 0.25), location: 0.00),
            .init(color: Color(red: 0.35, green: 0.23, blue: 0.32), location: 0.28),
            .init(color: Color(red: 0.37, green: 0.25, blue: 0.38), location: 0.46),
            .init(color: Color(red: 0.2, green: 0.15, blue: 0.32), location: 0.72),
            .init(color: Color(red: 0.16, green: 0.15, blue: 0.34), location: 1.00),
        ])
    }

    private func gradient(colorStops: [SwiftUI.Gradient.Stop]) -> some View {
        LinearGradient(
            stops: colorStops,
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
    }

}

public enum OnboardingGradientType {
    case `default`
    case highlights
}

struct EllipticalLightGradient: View {
    var body: some View {
        ZStack {
            // 5th gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.97, green: 0.73, blue: 0.67).opacity(0.5), location: 0.00),
                    Gradient.Stop(color: .clear, location: 1.00),
                ],
                center: UnitPoint(x: 0.2, y: 0.17),
                endRadiusFraction: 1
            )

            // 4th gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 1, green: 0.91, blue: 0.64).opacity(0.12), location: 0.00),
                    Gradient.Stop(color: .clear, location: 1.00),
                ],
                center: UnitPoint(x: 0.16, y: 0.86),
                endRadiusFraction: 1
            )

            // 3rd gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.93, green: 0.9, blue: 1).opacity(0.8), location: 0.00),
                    Gradient.Stop(color: .clear, location: 1.00),
                ],
                center: UnitPoint(x: 0.92, y: 0),
                endRadiusFraction: 1
            )

            // 2nd gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.93, green: 0.9, blue: 1).opacity(0.8), location: 0.00),
                    Gradient.Stop(color: .clear, location: 1.00),
                ],
                center: UnitPoint(x: 0.89, y: 1.07),
                endRadiusFraction: 1
            )

            // 1st gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.8, green: 0.85, blue: 1).opacity(0.58), location: 0.15),
                    Gradient.Stop(color: .clear, location: 1.00),
                ],
                center: UnitPoint(x: 1.02, y: 0.5),
                endRadiusFraction: 1
            )
        }
        .background(.white)
    }
}


private struct EllipticalDarkGradient: View {
    var body: some View {
        ZStack {
            // 5th Gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.17, green: 0.08, blue: 0.44).opacity(0.5), location: 0.00),
                    Gradient.Stop(color: Color(red: 0.17, green: 0.08, blue: 0.44).opacity(0), location: 1.00),
                ],
                center: UnitPoint(x: 0.2, y: 0.17),
                endRadiusFraction: 1
            )

            // 4th Gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 1, green: 1, blue: 0.54).opacity(0), location: 0.00),
                    Gradient.Stop(color: Color(red: 1, green: 0.91, blue: 0.64).opacity(0), location: 1.00),
                ],
                center: UnitPoint(x: 0.16, y: 0.86),
                endRadiusFraction: 1
            )

            // 3rd Gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.17, green: 0.08, blue: 0.44).opacity(0.8), location: 0.00),
                    Gradient.Stop(color: Color(red: 0.17, green: 0.08, blue: 0.44).opacity(0), location: 1.00),
                ],
                center: UnitPoint(x: 0.92, y: 0),
                endRadiusFraction: 1
            )

            // 2nd Gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.17, green: 0.08, blue: 0.44).opacity(0.8), location: 0.00),
                    Gradient.Stop(color: Color(red: 0.17, green: 0.08, blue: 0.44).opacity(0), location: 1.00),
                ],
                center: UnitPoint(x: 0.89, y: 1.07),
                endRadiusFraction: 1
            )

            // 1st Gradient
            EllipticalGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.89, green: 0.44, blue: 0.31).opacity(0.32), location: 0.15),
                    Gradient.Stop(color: Color(red: 0.89, green: 0.44, blue: 0.31).opacity(0), location: 1.00),
                ],
                center: UnitPoint(x: 1.0, y: 0.5),
                endRadiusFraction: 1
            )

        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.07))
    }
}

#Preview("Light Mode - Linear") {
    OnboardingGradient(type: .default)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode - Linear") {
    OnboardingGradient(type: .default)
        .preferredColorScheme(.dark)
}

#Preview("Light Mode - Elliptical") {
    OnboardingGradient(type: .highlights)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode - Elliptical") {
    OnboardingGradient(type: .highlights)
        .preferredColorScheme(.dark)
}
