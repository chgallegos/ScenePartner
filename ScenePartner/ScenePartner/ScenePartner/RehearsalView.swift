// RehearsalView.swift
import SwiftUI

struct RehearsalView: View {
    let script: Script
    let userCharacters: Set<String>
    let isImprovMode: Bool

    @StateObject private var engine: RehearsalEngine
    @StateObject private var teleprompter = TeleprompterEngine()
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @EnvironmentObject private var settings: AppSettings
    @State private var showScenePicker = false

    init(script: Script, userCharacters: Set<String>, isImprovMode: Bool, sceneDirection: SceneDirection = .empty) {
        self.script = script
        self.userCharacters = userCharacters
        self.isImprovMode = isImprovMode

        let settings = AppSettings()
        let voiceEngine: VoiceEngineProtocol
        if !settings.elevenLabsAPIKey.isEmpty && settings.useAIVoice {
            let el = ElevenLabsVoiceEngine(
                apiKey: settings.elevenLabsAPIKey,
                voiceID: settings.elevenLabsVoiceID
            )
            el.sceneDirection = sceneDirection
            voiceEngine = el
        } else {
            voiceEngine = SpeechManager()
        }

        _engine = StateObject(wrappedValue: RehearsalEngine(
            script: script, voiceEngine: voiceEngine, toneEngine: ToneEngine()))
    }

    var body: some View {
        VStack(spacing: 0) {
            TeleprompterView(script: script, engine: engine,
                             teleprompter: teleprompter, userCharacters: userCharacters)
                .frame(maxHeight: .infinity)
            Divider()
            statusStrip.padding(.horizontal).padding(.vertical, 8)
            Divider()
            controlBar.padding(.horizontal).padding(.vertical, 12).background(.ultraThinMaterial)
        }
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showScenePicker) {
            ScenePickerView(script: script) { engine.jump(to: $0); showScenePicker = false }
        }
        .onAppear {
            engine.setUserCharacters(userCharacters)
            engine.setImprovMode(isImprovMode)
            if engine.state.status == .idle { engine.start() }
        }
        .onChange(of: engine.state.currentLineIndex) { _, i in teleprompter.setFocus(to: i) }
    }

    // MARK: - Status Strip

    private var statusStrip: some View {
        HStack(spacing: 12) {
            Group {
                switch engine.state.status {
                case .idle:
                    Text("Ready")
                case .playingPartner:
                    Label(engine.currentLine?.speaker ?? "Partner", systemImage: "waveform")
                        .foregroundStyle(.blue)
                case .waitingForUser:
                    if engine.isListeningForUser {
                        Label("Speak your line...", systemImage: "mic.fill")
                            .foregroundStyle(.red)
                    } else {
                        Label("Your line — tap Next", systemImage: "hand.tap")
                            .foregroundStyle(.green)
                    }
                case .paused:
                    Label("Paused", systemImage: "pause.fill").foregroundStyle(.orange)
                case .finished:
                    Label("Scene complete!", systemImage: "checkmark.circle.fill").foregroundStyle(.purple)
                }
            }
            .font(.caption.weight(.medium))

            Spacer()

            // AI voice indicator
            if settings.useAIVoice && !settings.elevenLabsAPIKey.isEmpty {
                Label("AI Voice", systemImage: "brain")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.purple.opacity(0.12)).clipShape(Capsule())
            }

            // Listen mode toggle
            Button { engine.toggleListenMode() } label: {
                Label(engine.listenModeEnabled ? "Listen" : "Tap",
                      systemImage: engine.listenModeEnabled ? "mic.fill" : "hand.tap")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(engine.listenModeEnabled ? .red : .secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(engine.listenModeEnabled ? Color.red.opacity(0.12) : Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 32) {
            Button { engine.back() } label: {
                Image(systemName: "backward.end.fill").font(.title2)
            }.disabled(engine.state.currentLineIndex == 0)

            Button {
                switch engine.state.status {
                case .paused: engine.resume()
                case .idle: engine.start()
                case .finished: engine.start(from: 0)
                default: engine.pause()
                }
            } label: {
                Image(systemName: playPauseIcon).font(.largeTitle)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.blue))
                    .foregroundStyle(.white)
            }

            Button { engine.advance() } label: {
                Image(systemName: "forward.end.fill").font(.title2)
            }.disabled(engine.state.status != .waitingForUser)
        }
    }

    private var playPauseIcon: String {
        switch engine.state.status {
        case .paused, .idle, .finished: return "play.fill"
        default: return "pause.fill"
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Jump to Scene", systemImage: "list.bullet") { showScenePicker = true }
                Divider()
                Button("Increase Font", systemImage: "textformat.size.larger") { teleprompter.increaseFontSize() }
                Button("Decrease Font", systemImage: "textformat.size.smaller") { teleprompter.decreaseFontSize() }
                Button(teleprompter.isMirrorMode ? "Disable Mirror" : "Enable Mirror",
                       systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    teleprompter.toggleMirror()
                }
                Button(teleprompter.showOnlyUserLines ? "Show Full Script" : "Show My Lines Only",
                       systemImage: "person.crop.rectangle") { teleprompter.toggleUserOnlyMode() }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }
}

struct ScenePickerView: View {
    let script: Script
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(script.scenes) { scene in
                Button {
                    if let first = scene.lineIndices.first { onSelect(first) }
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(scene.heading).font(.headline)
                        Text("\(scene.lineIndices.count) lines").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Jump to Scene").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
