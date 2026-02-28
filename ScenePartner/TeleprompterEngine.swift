// TeleprompterEngine.swift
// ScenePartner — Manages teleprompter display state: scroll position,
//               font size, mirror mode, and which lines are visible.

import Foundation
import SwiftUI
import Combine

@MainActor
final class TeleprompterEngine: ObservableObject {

    // MARK: - Display Settings

    @Published var fontSize: CGFloat = 28
    @Published var scrollSpeed: Double = 1.0          // Multiplier: 0.5 = slow, 2.0 = fast
    @Published var isMirrorMode: Bool = false
    @Published var showOnlyUserLines: Bool = false    // Toggle: full script vs user-only

    // MARK: - Scroll State

    /// The line the teleprompter should centre on. Driven by RehearsalEngine.
    @Published private(set) var focusedLineIndex: Int = 0

    /// Whether auto-scroll is active.
    @Published var isAutoScrolling: Bool = false

    // MARK: - Derived

    /// Filter lines according to display mode.
    func visibleLines(from lines: [Line], userCharacters: Set<String>) -> [Line] {
        if showOnlyUserLines {
            return lines.filter {
                if let speaker = $0.speaker {
                    return userCharacters.contains(speaker.uppercased())
                }
                return false
            }
        }
        return lines
    }

    // MARK: - Controls

    func setFocus(to lineIndex: Int) {
        focusedLineIndex = lineIndex
    }

    func increaseFontSize() {
        fontSize = min(fontSize + 2, 72)
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 2, 14)
    }

    func toggleMirror() {
        isMirrorMode.toggle()
    }

    func toggleUserOnlyMode() {
        showOnlyUserLines.toggle()
    }
}
