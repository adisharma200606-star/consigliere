//
//  NotchContentView.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2025-04-19.
//

import SwiftUI

struct NotchContentView<Expanded, CompactLeading, CompactTrailing>: View where Expanded: View, CompactLeading: View, CompactTrailing: View {
    @ObservedObject private var dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>
    @Namespace private var namespace
    private let style: DynamicNotchStyle

    init(dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>, style: DynamicNotchStyle) {
        self.dynamicNotch = dynamicNotch
        self.style = style
    }

    private var shadowOpacity: CGFloat {
        if dynamicNotch.hoverBehavior.contains(.increaseShadow), dynamicNotch.isHovering {
            0.8
        } else if dynamicNotch.state != .expanded {
            0.0
        } else {
            0.5
        }
    }

    private var shadowRadius: CGFloat {
        if dynamicNotch.state == .hidden {
            0
        } else if dynamicNotch.isHovering, dynamicNotch.hoverBehavior.contains(.increaseShadow) {
            20
        } else {
            10
        }
    }

    /// One layer of the glow. Clear unless the notch is expanded and three colours were provided.
    private func glowColor(_ index: Int, _ opacity: Double) -> Color {
        guard dynamicNotch.state == .expanded, dynamicNotch.glowColors.count == 3 else { return .clear }
        let strength = max(0, min(1, dynamicNotch.glowStrength))
        return dynamicNotch.glowColors[index].opacity(opacity * strength)
    }

    var body: some View {
        ZStack {
            if style.isNotch {
                NotchView(dynamicNotch: dynamicNotch)
                    .foregroundStyle(.white)
            } else {
                NotchlessView(dynamicNotch: dynamicNotch)
            }
        }
        .shadow(
            color: .black.opacity(shadowOpacity),
            radius: shadowRadius
        )
        // CONSIGLIERE PATCH 2 of 3: the glow itself. It is tied to `state`, so it fades in and out inside the
        // same animation that opens and closes the notch, and a bouncy spring makes it flare for a moment.
        .shadow(color: glowColor(0, 0.45), radius: 14)
        .shadow(color: glowColor(1, 0.50), radius: 30, y: 10)
        .shadow(color: glowColor(2, 0.45), radius: 45)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.notchStyle, style)
        .animation(.snappy(duration: 0.4), value: dynamicNotch.isHovering)
        .onAppear {
            if dynamicNotch.namespace == nil {
                dynamicNotch.namespace = namespace
            }
        }
    }
}
