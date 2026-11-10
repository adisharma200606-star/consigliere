//
// DynamicNotchPanel.swift
// DynamicNotchKit
//
// Created by <Huy D.> on 2024-11-01.
//

import AppKit

final class DynamicNotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        self.hasShadow = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        // CONSIGLIERE PATCH 4: also show over full-screen apps (a full-screen video or game). Without
        // .fullScreenAuxiliary the notch, and his head beside it, vanish whenever something goes full screen.
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool {
        true
    }
}
