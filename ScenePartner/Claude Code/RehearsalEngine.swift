// RehearsalEngine.swift
// ScenePartner — The heart of the app. Drives the rehearsal state machine.
//
// State machine:
//   idle ──start()──► playingPartner ──done──► waitingForUser
//                                              │
//                         ◄──advance()─────────┘
//                         │
//                   playingPartner (next partner line) ──► ...
//                                          │
//                                    (end of script)
//                                          │
//                                       finished
//
// pause()/resume() work from any active state (playingPartner / waitingForUser).

import Foundation
import Combine

@MainActor
final class RehearsalEngine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: RehearsalState = RehearsalState()

    /// The current line the user/audience is focused on.
    var currentLine: Line? {
        guard state.currentLineIndex < script.lines.count else { return nil }
        return script.lines[state.currentLineIndex]
    }

    // MARK: - Dependencies

    private(set) var script: Script
    private let voiceEngine: VoiceEngineProtocol
    private let toneEngine: ToneEngine
    private var toneAnalysis: ToneAnalysis?

    // MARK: - Init

    init(script: Script,
         voiceEngine: VoiceEngineProtocol,
         toneEngine: ToneEngine = ToneEngine(),
         toneAnalysis: ToneAnalysis? = nil) {
        self.script = script
        self.voiceEngine = voiceEngine
        self.toneEngine = toneEngine
        self.toneAnalysis = toneAnalysis
    }

    // MARK: - Configuration

    /// Call before start(). Determines which characters the user plays.
    func setUserCharacters(_ characters: Set<String>) {
        state.userCharacters = Set(characters.map { $0.uppercased() })
    }

    func setImprovMode(_ on: Bool) {
        state.isImprovModeOn = on
    }

    func injectToneAnalysis(_ analysis: ToneAnalysis) {
        toneAnalysis = analysis
    }

    // MARK: - Controls

    /// Begin rehearsal from the current index (default: 0).
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
        if previous == .playingPartner {
            voiceEngine.pause()
        }
    }

    func resume() {
        guard state.status == .paused else { return }
        // Determine what we were doing before pause
        let line = currentLine
        if line?.type == .dialogue && isPartnerLine(line) {
            state.status = .playingPartner
            voiceEngine.resume()
        } else {
            state.status = .waitingForUser
        }
    }

    /// User manually advances their own line (tap-to-proceed MVP).
    func advance() {
        guard state.status == .waitingForUser else { return }
        markCurrentLineDone()
        moveToNextLine()
    }

    /// Skip back to the previous dialogue line.
    func back() {
        voiceEngine.stop()
        let target = previousDialogueIndex(before: state.currentLineIndex)
        state.currentLineIndex = target
        state.status = .idle
        processCurrentLine()
    }

    /// Jump to a specific line index (e.g. from scene picker).
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

    // MARK: - State Machine Core

    private func processCurrentLine() {
        guard state.currentLineIndex < script.lines.count else {
            state.status = .finished
            return
        }

        let line = script.lines[state.currentLineIndex]

        switch line.type {
        case .sceneHeading, .stageDirection:
            // Non-dialogue: advance silently
            moveToNextLine()

        case .dialogue:
            if isPartnerLine(line) {
                speakPartnerLine(line)
            } else {
                // User's line — wait for tap
                state.status = .waitingForUser
            }
        }
    }

    private func speakPartnerLine(_ line: Line) {
        state.status = .playingPartner

        let speaker = line.speaker ?? "NARRATOR"
        let sceneTones = sceneTones(for: line.sceneIndex)
        let profile = toneEngine.profile(for: speaker,
                                         sceneTones: sceneTones,
                                         analysis: toneAnalysis)

        voiceEngine.speak(text: line.text, profile: profile) { [weak self] in
            guard let self else { return }
            self.markCurrentLineDone()
            self.moveToNextLine()
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

    // MARK: - Helpers

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

    private func sceneTones(for sceneIndex: Int?) -> [String] {
        guard let sceneIndex else { return [] }
        // If tone analysis is available and maps scene tones, return them
        // For now: return the global scene_tone from analysis (per-scene mapping is a future feature)
        return toneAnalysis?.sceneTone ?? []
    }
}
