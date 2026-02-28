// SelfTapeView.swift
// ScenePartner — The main self-tape recording screen.
// Camera preview + teleprompter overlay + recording controls + take browser.

import SwiftUI
import AVFoundation

struct SelfTapeView: View {
    let script: Script
    let userCharacters: Set<String>
    let isImprovMode: Bool
    let sceneDirection: SceneDirection

    @StateObject private var camera = CameraEngine()
    @StateObject private var engine: RehearsalEngine
    @StateObject private var teleprompter = TeleprompterEngine()
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @EnvironmentObject private var settings: AppSettings

    @State private var takeManager: TakeManager? = nil
    @State private var showTakeBrowser = false
    @State private var lastSavedURL: URL? = nil
    @State private var showExportSuccess = false
    @State private var isExporting = false
    @State private var showTeleprompter = true

    init(script: Script, userCharacters: Set<String>,
         isImprovMode: Bool, sceneDirection: SceneDirection) {
        self.script = script
        self.userCharacters = userCharacters
        self.isImprovMode = isImprovMode
        self.sceneDirection = sceneDirection

        let s = AppSettings()
        let voiceEngine: VoiceEngineProtocol
        if !s.elevenLabsAPIKey.isEmpty && s.useAIVoice {
            let el = ElevenLabsVoiceEngine(apiKey: s.elevenLabsAPIKey, voiceID: s.elevenLabsVoiceID)
            el.sceneDirection = sceneDirection
            voiceEngine = el
        } else {
            voiceEngine = SpeechManager()
        }
        _engine = StateObject(wrappedValue: RehearsalEngine(
            script: script, voiceEngine: voiceEngine, toneEngine: ToneEngine()))
    }

    var body: some View {
        ZStack {
            // MARK: - Camera Background
            Color.black.ignoresSafeArea()

            if camera.permissionsGranted {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            } else {
                permissionPrompt
            }

            // MARK: - Teleprompter Overlay
            if showTeleprompter {
                VStack {
                    Spacer()
                    teleprompterOverlay
                }
                .ignoresSafeArea(edges: .bottom)
            }

            // MARK: - Top Controls
            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding()

            // MARK: - Countdown Overlay
            if let countdown = camera.countdownValue {
                countdownOverlay(countdown)
            }

            // MARK: - Recording Indicator
            if camera.isRecording {
                recordingBadge
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            engine.setUserCharacters(userCharacters)
            engine.setImprovMode(isImprovMode)
            setupTakeManager()
        }
        .onChange(of: engine.state.currentLineIndex) { _, i in teleprompter.setFocus(to: i) }
        .sheet(isPresented: $showTakeBrowser) {
            if let tm = takeManager {
                TakeBrowserView(takeManager: tm, scriptID: script.id) { url in
                    exportTake(url)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showExportSuccess {
                Label("Saved to Camera Roll", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.green.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showExportSuccess)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Back
            Button { } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.4)))
            }

            Spacer()

            // Script title
            Text(script.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.4)))

            Spacer()

            // Flip camera
            Button { camera.flipCamera() } label: {
                Image(systemName: "camera.rotate.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
        }
        .padding(.top, 50)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            // Rehearsal controls (play/pause/next)
            HStack(spacing: 24) {
                // Status
                statusPill
                Spacer()
                // Teleprompter toggle
                Button {
                    withAnimation { showTeleprompter.toggle() }
                } label: {
                    Image(systemName: showTeleprompter ? "text.bubble.fill" : "text.bubble")
                        .font(.title2).foregroundStyle(.white)
                        .padding(10).background(Circle().fill(.black.opacity(0.4)))
                }
                // Takes browser
                Button { showTakeBrowser = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "film.stack")
                            .font(.title2).foregroundStyle(.white)
                            .padding(10).background(Circle().fill(.black.opacity(0.4)))
                        if let count = takeManager?.takes.count, count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(Color.red))
                                .offset(x: 4, y: -4)
                        }
                    }
                }
            }

            // Main record button row
            HStack(spacing: 40) {
                // Play/pause rehearsal
                Button {
                    switch engine.state.status {
                    case .idle: engine.start()
                    case .paused: engine.resume()
                    case .finished: engine.start(from: 0)
                    default: engine.pause()
                    }
                } label: {
                    Image(systemName: engine.state.status == .paused ||
                          engine.state.status == .idle ||
                          engine.state.status == .finished ? "play.fill" : "pause.fill")
                        .font(.title).foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.black.opacity(0.5)))
                }

                // Record button
                recordButton

                // Advance (tap to advance user line)
                Button { engine.advance() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title).foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(
                            engine.state.status == .waitingForUser ? Color.green.opacity(0.6) : .black.opacity(0.4)))
                }
                .disabled(engine.state.status != .waitingForUser)
            }
            .padding(.bottom, 40)
        }
    }

    private var recordButton: some View {
        Button {
            if camera.isRecording {
                camera.stopRecording { url in
                    if let url {
                        lastSavedURL = url
                        takeManager?.addTake(url: url)
                        // Auto-export to camera roll
                        camera.exportToPhotoLibrary(url: url) { success in
                            if success {
                                withAnimation { showExportSuccess = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation { showExportSuccess = false }
                                }
                            }
                        }
                    }
                }
                engine.stop()
            } else {
                let takeNum = takeManager?.takes.count ?? 0 + 1
                camera.startCountdownAndRecord(
                    scriptID: script.id, sceneIndex: 0, takeNumber: takeNum)
                // Start rehearsal after countdown
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
                    engine.start(from: 0)
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(camera.isRecording ? Color.red : Color.white)
                    .frame(width: 72, height: 72)
                if camera.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                }
            }
            .overlay(Circle().stroke(Color.white, lineWidth: 3).frame(width: 84, height: 84))
        }
    }

    // MARK: - Teleprompter Overlay

    private var teleprompterOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Show only a few lines around current
            let visible = visibleLines
            ForEach(visible, id: \.index) { line in
                if line.type == .dialogue {
                    VStack(alignment: .leading, spacing: 2) {
                        if let speaker = line.speaker {
                            Text(speaker)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isUserLine(line) ? Color.green.opacity(0.9) : Color.blue.opacity(0.9))
                        }
                        Text(line.text)
                            .font(.system(size: teleprompter.fontSize * 0.7, weight: .medium))
                            .foregroundStyle(line.index == engine.state.currentLineIndex ?
                                           Color.white : Color.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
            }
        }
        .padding(.bottom, 180)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var visibleLines: [Line] {
        let all = script.lines.filter { $0.type == .dialogue }
        let current = engine.state.currentLineIndex
        return all.filter { abs($0.index - current) <= 3 }
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        Group {
            switch engine.state.status {
            case .waitingForUser:
                Label(engine.isListeningForUser ? "Listening..." : "Your line",
                      systemImage: engine.isListeningForUser ? "mic.fill" : "hand.tap")
                    .foregroundStyle(engine.isListeningForUser ? .red : .green)
            case .playingPartner:
                Label(engine.currentLine?.speaker ?? "Partner", systemImage: "waveform")
                    .foregroundStyle(.blue)
            case .finished:
                Label("Done", systemImage: "checkmark.circle").foregroundStyle(.purple)
            default:
                Label("Ready", systemImage: "play.circle").foregroundStyle(.white)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.5)))
        .foregroundStyle(.white)
    }

    // MARK: - Countdown Overlay

    private func countdownOverlay(_ value: Int) -> some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            Text("\(value)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
                .id(value)
        }
    }

    // MARK: - Recording Badge

    private var recordingBadge: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                        .opacity(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3)
                    Text(formattedDuration)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding()
            }
            Spacer()
        }
        .padding(.top, 50)
    }

    private var formattedDuration: String {
        let t = Int(camera.recordingDuration)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: - Helpers

    private func isUserLine(_ line: Line) -> Bool {
        guard let speaker = line.speaker else { return false }
        return userCharacters.contains(speaker.uppercased())
    }

    private func setupTakeManager() {
        let urls = camera.savedTakes(scriptID: script.id, sceneIndex: 0)
        takeManager = TakeManager(scriptID: script.id, sceneIndex: 0, savedURLs: urls)
    }

    private func exportTake(_ url: URL) {
        isExporting = true
        camera.exportToPhotoLibrary(url: url) { success in
            isExporting = false
            if success {
                withAnimation { showExportSuccess = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showExportSuccess = false }
                }
            }
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 60)).foregroundStyle(.secondary)
            Text("Camera Access Required")
                .font(.title2.weight(.semibold))
            Text("ScenePartner needs camera access to record your self-tapes.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Grant Access") { camera.requestPermissions() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Take Browser

struct TakeBrowserView: View {
    @ObservedObject var takeManager: TakeManager
    let scriptID: UUID
    let onExport: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if takeManager.takes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "film.stack").font(.system(size: 50)).foregroundStyle(.secondary)
                        Text("No takes yet").font(.title3.weight(.semibold))
                        Text("Record a take to see it here.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(takeManager.takes) { take in
                                TakeThumbnailView(
                                    take: take,
                                    isHero: takeManager.heroTakeID == take.id,
                                    onSetHero: { takeManager.setHero(take) },
                                    onExport: { onExport(take.url) },
                                    onDelete: { takeManager.deleteTake(take) }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Takes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Take Thumbnail

struct TakeThumbnailView: View {
    let take: Take
    let isHero: Bool
    let onSetHero: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let thumb = take.thumbnail {
                    Image(uiImage: thumb)
                        .resizable().scaledToFill()
                        .frame(height: 120).clipped()
                } else {
                    Rectangle().fill(Color(.secondarySystemBackground))
                        .frame(height: 120)
                    ProgressView()
                }

                // Hero badge
                if isHero {
                    VStack {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow).font(.caption)
                                .padding(4)
                                .background(Circle().fill(.black.opacity(0.6)))
                                .padding(4)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Duration
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(take.formattedDuration)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .padding(4)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isHero ? Color.yellow : Color.clear, lineWidth: 2))

            Text(take.displayName).font(.caption.weight(.medium))

            HStack(spacing: 8) {
                Button { onSetHero() } label: {
                    Image(systemName: isHero ? "star.fill" : "star")
                        .font(.caption).foregroundStyle(isHero ? .yellow : .secondary)
                }
                Button { onExport() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption).foregroundStyle(.blue)
                }
                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}
