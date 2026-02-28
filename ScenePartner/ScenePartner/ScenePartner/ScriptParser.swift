// ScriptParser.swift
// ScenePartner — Converts raw script text into structured Script model.
//
// Supported format (relaxed):
//   SCENE / INT. / EXT. headings → LineType.sceneHeading
//   ALL-CAPS word(s) alone on a line → character name (speaker of next dialogue)
//   Lines starting with ( or [ → stage direction
//   Anything else after a known speaker → dialogue

import Foundation

final class ScriptParser {

    // MARK: - Public API

    /// Parse raw script text and return a fully populated Script.
    /// This is synchronous and CPU-only — safe to call offline.
    func parse(rawText: String, title: String) -> Script {
        let rawLines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var lines: [Line] = []
        var scenes: [Scene] = []
        var characterCounts: [String: Int] = [:]

        var currentSpeaker: String? = nil
        var currentSceneIndex: Int = -1
        var globalLineIndex: Int = 0

        for raw in rawLines {
            guard !raw.isEmpty else {
                // Blank line resets pending speaker
                currentSpeaker = nil
                continue
            }

            // --- Scene heading detection ---
            if isSceneHeading(raw) {
                currentSpeaker = nil
                let scene = Scene(index: scenes.count, heading: raw)
                scenes.append(scene)
                currentSceneIndex = scenes.count - 1

                let line = Line(
                    index: globalLineIndex,
                    speaker: nil,
                    text: raw,
                    type: .sceneHeading,
                    sceneIndex: currentSceneIndex
                )
                lines.append(line)
                appendLineIndex(globalLineIndex, to: &scenes, at: currentSceneIndex)
                globalLineIndex += 1
                continue
            }

            // --- Stage direction detection ---
            if isStageDirection(raw) {
                let line = Line(
                    index: globalLineIndex,
                    speaker: nil,
                    text: raw,
                    type: .stageDirection,
                    sceneIndex: currentSceneIndex >= 0 ? currentSceneIndex : nil
                )
                lines.append(line)
                appendLineIndex(globalLineIndex, to: &scenes, at: currentSceneIndex)
                globalLineIndex += 1
                // Stage directions don't reset currentSpeaker (beat/pause mid-speech)
                continue
            }

            // --- Character name detection ---
            if isCharacterName(raw) {
                currentSpeaker = raw.uppercased()
                // Don't create a line for the name itself — it's metadata
                continue
            }

            // --- Dialogue ---
            // Anything remaining after establishing a speaker is dialogue
            if let speaker = currentSpeaker {
                let line = Line(
                    index: globalLineIndex,
                    speaker: speaker,
                    text: raw,
                    type: .dialogue,
                    sceneIndex: currentSceneIndex >= 0 ? currentSceneIndex : nil
                )
                lines.append(line)
                appendLineIndex(globalLineIndex, to: &scenes, at: currentSceneIndex)
                characterCounts[speaker, default: 0] += 1
                globalLineIndex += 1
                // Don't reset speaker — multi-paragraph speeches
            } else {
                // Unattributed prose — treat as stage direction
                let line = Line(
                    index: globalLineIndex,
                    speaker: nil,
                    text: raw,
                    type: .stageDirection,
                    sceneIndex: currentSceneIndex >= 0 ? currentSceneIndex : nil
                )
                lines.append(line)
                appendLineIndex(globalLineIndex, to: &scenes, at: currentSceneIndex)
                globalLineIndex += 1
            }
        }

        // If no scenes were found, create a synthetic one
        if scenes.isEmpty {
            let allIndices = Array(0..<lines.count)
            scenes.append(Scene(index: 0, heading: "Scene 1", lineIndices: allIndices))
            lines = lines.map {
                var l = $0; l.sceneIndex = 0; return l
            }
        }

        let characters = characterCounts.map {
            Character(name: $0.key, lineCount: $0.value)
        }.sorted { $0.lineCount > $1.lineCount }

        return Script(
            title: title,
            rawText: rawText,
            lines: lines,
            scenes: scenes,
            characters: characters
        )
    }

    // MARK: - Detection Helpers

    private func isSceneHeading(_ text: String) -> Bool {
        let upper = text.uppercased()
        let prefixes = ["SCENE ", "INT.", "EXT.", "INT/EXT", "ACT "]
        if prefixes.contains(where: { upper.hasPrefix($0) }) { return true }
        // Pure "SCENE N" pattern
        let scenePattern = #"^SCENE\s+\d+"#
        return upper.range(of: scenePattern, options: .regularExpression) != nil
    }

    private func isStageDirection(_ text: String) -> Bool {
        return text.hasPrefix("(") || text.hasPrefix("[")
    }

    private func isCharacterName(_ text: String) -> Bool {
        // All-caps, no punctuation except spaces/hyphens, 1–4 words, no lowercase
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let allowedChars = CharacterSet.uppercaseLetters
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-'"))
        let isAllCaps = trimmed.unicodeScalars.allSatisfy { allowedChars.contains($0) }
        let wordCount = trimmed.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }.count
        // Reject very long all-caps lines (probably scene headings we missed or uppercase prose)
        return isAllCaps && wordCount <= 5 && trimmed.count >= 2
    }

    private func appendLineIndex(_ index: Int, to scenes: inout [Scene], at sceneIndex: Int) {
        guard sceneIndex >= 0 && sceneIndex < scenes.count else { return }
        scenes[sceneIndex].lineIndices.append(index)
    }
}
