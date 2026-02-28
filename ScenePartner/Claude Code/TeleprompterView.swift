// TeleprompterView.swift
// ScenePartner — Scrollable, highlighted teleprompter display.
//
// Behaviour:
//   • Full script rendered in a ScrollView
//   • Current line smoothly scrolled into view
//   • Line color-coded by type and ownership
//   • Mirror mode via scaleEffect(x: -1)
//   • Font size driven by TeleprompterEngine

import SwiftUI

struct TeleprompterView: View {

    let script: Script
    @ObservedObject var engine: RehearsalEngine
    @ObservedObject var teleprompter: TeleprompterEngine
    let userCharacters: Set<String>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleLines) { line in
                        lineView(for: line)
                            .id(line.index)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(highlightBackground(for: line))
                            .animation(.easeInOut(duration: 0.2), value: engine.state.currentLineIndex)
                    }
                }
                .padding(.vertical, 40)
            }
            .scaleEffect(x: teleprompter.isMirrorMode ? -1 : 1, y: 1)
            .onChange(of: teleprompter.focusedLineIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Line Rendering

    @ViewBuilder
    private func lineView(for line: Line) -> some View {
        switch line.type {
        case .sceneHeading:
            Text(line.text)
                .font(.system(size: teleprompter.fontSize * 0.75, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.secondary)

        case .stageDirection:
            Text(line.text)
                .font(.system(size: teleprompter.fontSize * 0.8, design: .serif))
                .italic()
                .foregroundStyle(.secondary)

        case .dialogue:
            VStack(alignment: .leading, spacing: 2) {
                if let speaker = line.speaker {
                    Text(speaker)
                        .font(.system(size: teleprompter.fontSize * 0.7, weight: .semibold))
                        .foregroundStyle(speakerColor(for: speaker))
                }
                Text(line.text)
                    .font(.system(size: teleprompter.fontSize, weight: .medium))
                    .foregroundStyle(isCurrent(line) ? .primary : .secondary)
            }
        }
    }

    // MARK: - Styling Helpers

    private func highlightBackground(for line: Line) -> some View {
        Group {
            if isCurrent(line) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.12))
            } else {
                Color.clear
            }
        }
    }

    private func isCurrent(_ line: Line) -> Bool {
        line.index == engine.state.currentLineIndex
    }

    private func isUserLine(_ line: Line) -> Bool {
        guard let speaker = line.speaker else { return false }
        return userCharacters.contains(speaker.uppercased())
    }

    private func speakerColor(for speaker: String) -> Color {
        if userCharacters.contains(speaker.uppercased()) {
            return .green
        }
        return .blue
    }

    private var visibleLines: [Line] {
        teleprompter.visibleLines(from: script.lines,
                                  userCharacters: userCharacters)
    }
}
