// RehearsalView.swift
// ScenePartner — Main rehearsal screen combining teleprompter + controls.
//
// Layout:
//   ┌────────────────────────────┐
//   │  TeleprompterView          │  (scrollable script)
//   │  [current line highlighted]│
//   ├────────────────────────────┤
//   │  Status strip              │
//   ├────────────────────────────┤
//   │  Control bar               │  (play/pause, back, next, jump)
//   └────────────────────────────┘

import SwiftUI

struct RehearsalView: View {

    // MARK: - Inputs

    let script: Script
    let userCharacters: Set<String>
    let isImprovMode: Bool

    // MARK: - Engine

    @StateObject private var engine: RehearsalEngine
    @StateObject private var teleprompter: TeleprompterEngine

    // MARK: - Environment

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.dismiss) private var dismiss

    // MARK: - UI State

    @State private var showScenePicker = false
    @State private var showSettings = false

    // MARK: - Init

    init(script: Script, userCharacters: Set<String>, isImprovMode: Bool) {
        self.script = script
        self.userCharacters = userCharacters
        self.isImprovMode = isImprovMode

        let speechManager = SpeechManager()
        let toneEngine = ToneEngine()
        let eng = RehearsalEngine(script: script,
                                   voiceEngine: speechManager,
                                   toneEngine: toneEngine)
        eng.setUserCharacters(userCharacters)
        eng.setImprovMode(isImprovMode)
        _engine = StateObject(wrappedValue: eng)
        _teleprompter = StateObject(wrappedValue: TeleprompterEngine())
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Teleprompter
                TeleprompterView(
                    script: script,
                    engine: engine,
                    teleprompter: teleprompter,
                    userCharacters: userCharacters
                )
                .frame(maxHeight: .infinity)

                Divider()

                // Status strip
                statusStrip
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                // Control bar
                controlBar
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showScenePicker) {
            ScenePickerView(script: script) { lineIndex in
                engine.jump(to: lineIndex)
                showScenePicker = false
            }
        }
        .onAppear {
            if engine.state.status == .idle {
                engine.start()
            }
        }
        .onChange(of: engine.state.currentLineIndex) { _, newIndex in
            teleprompter.setFocus(to: newIndex)
        }
    }

    // MARK: - Status Strip

    private var statusStrip: some View {
        HStack {
            statusLabel
            Spacer()
            if engine.state.isImprovModeOn {
                Label("IMPROV", systemImage: "wand.and.stars")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }
            if !connectivity.isConnected {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusLabel: some View {
        Group {
            switch engine.state.status {
            case .idle:
                Text("Ready")
            case .playingPartner:
                if let line = engine.currentLine {
                    Label(line.speaker ?? "Partner", systemImage: "waveform")
                        .foregroundStyle(.blue)
                }
            case .waitingForUser:
                Label("Your line — tap Next", systemImage: "hand.tap")
                    .foregroundStyle(.green)
            case .paused:
                Label("Paused", systemImage: "pause.fill")
                    .foregroundStyle(.orange)
            case .finished:
                Label("Scene complete!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.purple)
            }
        }
        .font(.caption.weight(.medium))
        .animation(.easeInOut, value: engine.state.status)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 32) {
            // Back
            Button { engine.back() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
            }
            .disabled(engine.state.currentLineIndex == 0)

            // Play / Pause
            Button {
                switch engine.state.status {
                case .paused:     engine.resume()
                case .idle:       engine.start()
                case .finished:   engine.start(from: 0)
                default:          engine.pause()
                }
            } label: {
                Image(systemName: playPauseIcon)
                    .font(.largeTitle)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.blue))
                    .foregroundStyle(.white)
            }

            // Next (user line advance)
            Button { engine.advance() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
            }
            .disabled(engine.state.status != .waitingForUser)
        }
    }

    private var playPauseIcon: String {
        switch engine.state.status {
        case .paused, .idle, .finished: return "play.fill"
        default: return "pause.fill"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Jump to Scene", systemImage: "list.bullet") {
                    showScenePicker = true
                }
                Divider()
                Button("Increase Font", systemImage: "textformat.size.larger") {
                    teleprompter.increaseFontSize()
                }
                Button("Decrease Font", systemImage: "textformat.size.smaller") {
                    teleprompter.decreaseFontSize()
                }
                Button(teleprompter.isMirrorMode ? "Disable Mirror" : "Enable Mirror",
                       systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    teleprompter.toggleMirror()
                }
                Button(teleprompter.showOnlyUserLines ? "Show Full Script" : "Show My Lines Only",
                       systemImage: "person.crop.rectangle") {
                    teleprompter.toggleUserOnlyMode()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - ScenePickerView

struct ScenePickerView: View {
    let script: Script
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(script.scenes) { scene in
                Button {
                    if let firstLine = scene.lineIndices.first {
                        onSelect(firstLine)
                    }
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(scene.heading)
                            .font(.headline)
                        Text("\(scene.lineIndices.count) lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Jump to Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
