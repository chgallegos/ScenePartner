// RehearsalEngine.swift
import Foundation
import Combine

@MainActor
final class RehearsalEngine: ObservableObject {

    @Published private(set) var state: RehearsalState = RehearsalState()

    var currentLine: Line? {
        guard state.currentLineIndex < script.lines.count else { return nil }
        return script.lines[state.currentLineIndex]
    }

    private(set) var script: Script
    private let voiceEngine: VoiceEngineProtocol
    private let toneEngine: ToneEngine
    private var toneAnalysis: ToneAnalysis?

    init(script: Script, voiceEngine: VoiceEngineProtocol, toneEngine: ToneEngine,
         toneAnalysis: ToneAnalysis? = nil) {
        self.script = script
        self.voiceEngine = voiceEngine
        self.toneEngine = toneEngine
        self.toneAnalysis = toneAnalysis
    }

    func setUserCharacters(_ characters: Set<String>) {
        state.userCharacters = Set(characters.map { $0.uppercased() })
    }

    func setImprovMode(_ on: Bool) { state.isImprovModeOn = on }

    func injectToneAnalysis(_ analysis: ToneAnalysis) { toneAnalysis = analysis }

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
        if previous == .playingPartner { voiceEngine.pause() }
    }

    func resume() {
        guard state.status == .paused else { return }
        if currentLine?.type == .dialogue && isPartnerLine(currentLine) {
            state.status = .playingPartner
            voiceEngine.resume()
        } else {
            state.status = .waitingForUser
        }
    }

    func advance() {
        guard state.status == .waitingForUser else { return }
        markCurrentLineDone()
        moveToNextLine()
    }

    func back() {
        voiceEngine.stop()
        state.currentLineIndex = previousDialogueIndex(before: state.currentLineIndex)
        state.status = .idle
        processCurrentLine()
    }

    func jump(to index: Int) {
        guard index >= 0 && index < script.lines.count else { return }
        voiceEngine.stop()
        state.currentLineIndex = index
        state.status = .idle
        processCurrentLine()
    }

    func stop() {
        voiceEngine.stop()
        state.status = .idle
        state.currentLineIndex = 0
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
            else { state.status = .waitingForUser }
        }
    }

    private func speakPartnerLine(_ line: Line) {
        state.status = .playingPartner
        let speaker = line.speaker ?? "NARRATOR"
        let tones = toneAnalysis?.sceneTone ?? []
        let profile = toneEngine.profile(for: speaker, sceneTones: tones, analysis: toneAnalysis)

        voiceEngine.speak(text: line.text, profile: profile) { [weak self] in
            // Dispatch back to MainActor since the completion fires from a background queue
            Task { @MainActor [weak self] in
                self?.markCurrentLineDone()
                self?.moveToNextLine()
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
