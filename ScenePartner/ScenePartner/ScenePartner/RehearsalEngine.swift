// RehearsalEngine.swift
import Foundation
import Combine

@MainActor
final class RehearsalEngine: ObservableObject {

    @Published private(set) var state: RehearsalState = RehearsalState()
    @Published private(set) var isListeningForUser = false

    var currentLine: Line? {
        guard state.currentLineIndex < script.lines.count else { return nil }
        return script.lines[state.currentLineIndex]
    }

    private(set) var script: Script
    private let voiceEngine: VoiceEngineProtocol
    private let toneEngine: ToneEngine
    private let speechRecognizer: SpeechRecognizer
    private var toneAnalysis: ToneAnalysis?

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
                startListeningIfEnabled()
            }
        }
    }

    private func speakPartnerLine(_ line: Line) {
        state.status = .playingPartner
        let speaker = line.speaker ?? "NARRATOR"
        let tones = toneAnalysis?.sceneTone ?? []
        let profile = toneEngine.profile(for: speaker, sceneTones: tones, analysis: toneAnalysis)

        voiceEngine.speak(text: line.text, profile: profile) { [weak self] in
            Task { @MainActor [weak self] in
                self?.markCurrentLineDone()
                self?.moveToNextLine()
            }
        }
    }

    private func startListeningIfEnabled() {
        guard listenModeEnabled else { return }
        guard speechRecognizer.permissionGranted else {
            speechRecognizer.requestPermission()
            return
        }
        isListeningForUser = true
        speechRecognizer.startListening { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state.status == .waitingForUser else { return }
                self.isListeningForUser = false
                self.markCurrentLineDone()
                self.moveToNextLine()
            }
        }
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
