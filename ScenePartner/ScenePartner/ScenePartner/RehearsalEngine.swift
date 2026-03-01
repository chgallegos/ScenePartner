// RehearsalEngine.swift
import Foundation
import Combine

@MainActor
final class RehearsalEngine: ObservableObject {

    @Published private(set) var state: RehearsalState = RehearsalState()
    @Published private(set) var isListeningForUser = false

    /// Live microphone level (0.0-1.0) — for UI meter display
    var audioLevel: Float { speechRecognizer.audioLevel }

    var currentLine: Line? {
        guard state.currentLineIndex < script.lines.count else { return nil }
        return script.lines[state.currentLineIndex]
    }

    private(set) var script: Script
    private let voiceEngine: VoiceEngineProtocol
    private let toneEngine: ToneEngine
    private let speechRecognizer: SpeechRecognizer
    private var toneAnalysis: ToneAnalysis?
    private var adaptiveDirectors: [String: AdaptiveDirector] = [:]

    // Whether listen mode is active
    var listenModeEnabled: Bool = true

    init(script: Script, voiceEngine: VoiceEngineProtocol, toneEngine: ToneEngine,
         toneAnalysis: ToneAnalysis? = nil) {
        self.script = script
        self.voiceEngine = voiceEngine
        self.toneEngine = toneEngine
        self.speechRecognizer = SpeechRecognizer()
        self.toneAnalysis = toneAnalysis
    }

    func setUserCharacters(_ characters: Set<String>) {
        state.userCharacters = Set(characters.map { $0.uppercased() })
    }

    func setImprovMode(_ on: Bool) { state.isImprovModeOn = on }
    func injectToneAnalysis(_ analysis: ToneAnalysis) { toneAnalysis = analysis }

    /// Call after setUserCharacters to set up adaptive directors for partner characters
    func setupAdaptiveDirectors(sceneDirection: SceneDirection, openAIKey: String) {
        guard !openAIKey.isEmpty else { return }
        let partnerNames = script.characters
            .map { $0.name }
            .filter { !state.userCharacters.contains($0) }
        for name in partnerNames {
            let initialDir = sceneDirection.characterDirections[name] ?? .empty(for: name)
            adaptiveDirectors[name] = AdaptiveDirector(
                characterName: name,
                initialDirection: initialDir,
                openAIKey: openAIKey
            )
        }
        print("[RehearsalEngine] 🧠 Adaptive directors set up for: \(partnerNames.joined(separator: ", "))")
    }

    // MARK: - Controls

    func start(from index: Int = 0) {
        guard state.status == .idle || state.status == .finished else { return }
        state.currentLineIndex = index
        state.sessionStartedAt = Date()
        state.completedLineIndices = []
        processCurrentLine()
    }

    func pause() {
        guard state.status == .playingPartner || state.status == .waitingForUser else { return }
        let previous = state.status
        state.status = .paused
        speechRecognizer.stopListening()
        isListeningForUser = false
        if previous == .playingPartner { voiceEngine.pause() }
    }

    func resume() {
        guard state.status == .paused else { return }
        if currentLine?.type == .dialogue && isPartnerLine(currentLine) {
            state.status = .playingPartner
            voiceEngine.resume()
        } else {
            state.status = .waitingForUser
            startListeningIfEnabled()
        }
    }

    /// Manual tap-to-advance (fallback when listen mode is off or times out)
    func advance() {
        guard state.status == .waitingForUser else { return }
        speechRecognizer.stopListening()
        isListeningForUser = false
        markCurrentLineDone()
        moveToNextLine()
    }

    func back() {
        speechRecognizer.stopListening()
        isListeningForUser = false
        voiceEngine.stop()
        state.currentLineIndex = previousDialogueIndex(before: state.currentLineIndex)
        state.status = .idle
        processCurrentLine()
    }

    func jump(to index: Int) {
        guard index >= 0 && index < script.lines.count else { return }
        speechRecognizer.stopListening()
        isListeningForUser = false
        voiceEngine.stop()
        state.currentLineIndex = index
        state.status = .idle
        processCurrentLine()
    }

    func stop() {
        speechRecognizer.stopListening()
        isListeningForUser = false
        voiceEngine.stop()
        state.status = .idle
        state.currentLineIndex = 0
    }

    func toggleListenMode() {
        listenModeEnabled.toggle()
        if !listenModeEnabled {
            speechRecognizer.stopListening()
            isListeningForUser = false
        } else if state.status == .waitingForUser {
            startListeningIfEnabled()
        }
    }

    // MARK: - State Machine

    private func processCurrentLine() {
        guard state.currentLineIndex < script.lines.count else {
            state.status = .finished
            return
        }
        let line = script.lines[state.currentLineIndex]
        switch line.type {
        case .sceneHeading, .stageDirection:
            moveToNextLine()
        case .dialogue:
            if isPartnerLine(line) { speakPartnerLine(line) }
            else {
                state.status = .waitingForUser
                // Record user's line text for adaptive analysis
                for director in adaptiveDirectors.values {
                    director.recordLine(speaker: line.speaker ?? "USER", text: line.text)
                }
                startListeningIfEnabled()
            }
        }
    }

    private func speakPartnerLine(_ line: Line) {
        state.status = .playingPartner
        let speaker = line.speaker ?? "NARRATOR"
        let tones = toneAnalysis?.sceneTone ?? []
        let profile = toneEngine.profile(for: speaker, sceneTones: tones, analysis: toneAnalysis)

        // Update ElevenLabs direction from adaptive director if available
        if let director = adaptiveDirectors[speaker],
           let el = voiceEngine as? ElevenLabsVoiceEngine {
            var dir = el.sceneDirection
            dir.characterDirections[speaker] = director.currentDirection
            el.sceneDirection = dir
        }

        // Record this line for adaptive analysis
        adaptiveDirectors[speaker]?.recordLine(speaker: speaker, text: line.text)

        voiceEngine.speak(text: line.text, profile: profile) { [weak self] in
            Task { @MainActor [weak self] in
                self?.markCurrentLineDone()
                self?.moveToNextLine()
            }
        }
    }

    private func startListeningIfEnabled() {
        guard listenModeEnabled else { return }

        // Simulator has no real mic — skip listen mode automatically
        #if targetEnvironment(simulator)
        print("[RehearsalEngine] Simulator detected — listen mode disabled, use tap to advance")
        return
        #else

        guard speechRecognizer.permissionGranted else {
            speechRecognizer.requestPermission()
            return
        }
        isListeningForUser = true
        print("[RehearsalEngine] 🎤 Starting listen mode for user line")
        speechRecognizer.startListening { [weak self] spokenText in
            Task { @MainActor [weak self] in
                guard let self, self.state.status == .waitingForUser else { return }
                print("[RehearsalEngine] 📝 User spoke: \"\(spokenText)\" — advancing")
                self.isListeningForUser = false
                self.markCurrentLineDone()
                self.moveToNextLine()
            }
        }
        #endif
    }

    private func moveToNextLine() {
        let next = state.currentLineIndex + 1
        if next >= script.lines.count {
            state.status = .finished
        } else {
            state.currentLineIndex = next
            processCurrentLine()
        }
    }

    private func markCurrentLineDone() {
        state.completedLineIndices.insert(state.currentLineIndex)
    }

    private func isPartnerLine(_ line: Line?) -> Bool {
        guard let line, let speaker = line.speaker else { return false }
        return !state.userCharacters.contains(speaker.uppercased())
    }

    private func previousDialogueIndex(before index: Int) -> Int {
        var i = index - 1
        while i >= 0 {
            if script.lines[i].type == .dialogue { return i }
            i -= 1
        }
        return 0
    }
}
