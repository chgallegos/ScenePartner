// ScriptModels.swift
// ScenePartner — Core data models for scripts, scenes, lines, and characters.

import Foundation

// MARK: - Line

/// The atomic unit of a script. Every parsed element becomes a Line.
struct Line: Identifiable, Codable, Equatable {
    let id: UUID
    var index: Int              // Global, 0-based position in the flat script
    var speaker: String?        // nil for non-dialogue types
    var text: String
    var type: LineType
    var sceneIndex: Int?        // Which scene this line belongs to

    enum LineType: String, Codable {
        case dialogue           // A character speaks
        case stageDirection     // Parenthetical or bracket notes
        case sceneHeading       // SCENE 1, INT. KITCHEN, etc.
    }

    init(id: UUID = UUID(), index: Int, speaker: String? = nil, text: String,
         type: LineType, sceneIndex: Int? = nil) {
        self.id = id
        self.index = index
        self.speaker = speaker
        self.text = text
        self.type = type
        self.sceneIndex = sceneIndex
    }
}

// MARK: - Scene

struct Scene: Identifiable, Codable, Equatable {
    let id: UUID
    var index: Int              // 0-based scene order
    var heading: String         // Display heading extracted from script
    var lineIndices: [Int]      // Indices into Script.lines[] for lines in this scene

    init(id: UUID = UUID(), index: Int, heading: String, lineIndices: [Int] = []) {
        self.id = id
        self.index = index
        self.heading = heading
        self.lineIndices = lineIndices
    }
}

// MARK: - Character

struct Character: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String            // Normalised uppercase name as it appears in script
    var lineCount: Int          // Total dialogue lines for this character

    init(id: UUID = UUID(), name: String, lineCount: Int = 0) {
        self.id = id
        self.name = name
        self.lineCount = lineCount
    }
}

// MARK: - Script

/// The top-level container persisted to disk.
struct Script: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var rawText: String         // Original pasted / imported text — kept for re-parsing
    var lines: [Line]
    var scenes: [Scene]
    var characters: [Character]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, rawText: String,
         lines: [Line] = [], scenes: [Scene] = [], characters: [Character] = [],
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.rawText = rawText
        self.lines = lines
        self.scenes = scenes
        self.characters = characters
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convenience: return all dialogue lines for a given speaker name.
    func lines(for speaker: String) -> [Line] {
        lines.filter { $0.speaker?.uppercased() == speaker.uppercased() && $0.type == .dialogue }
    }
}

// MARK: - RehearsalState

/// The complete rehearsal state machine state.  All transitions are driven by
/// RehearsalEngine — never mutated directly from the UI.
enum RehearsalStatus: String, Codable {
    case idle               // Not yet started
    case playingPartner     // AI/TTS is speaking a partner line
    case waitingForUser     // User must advance their own line
    case paused             // User pressed pause mid-rehearsal
    case finished           // End of script reached
}

struct RehearsalState: Equatable {
    var status: RehearsalStatus = .idle
    var currentLineIndex: Int = 0           // Index into Script.lines[]
    var userCharacters: Set<String> = []    // Character names owned by the user
    var isImprovModeOn: Bool = false
    var sessionStartedAt: Date? = nil
    var completedLineIndices: Set<Int> = []
}

// MARK: - VoiceProfile

/// Parameters that influence TTS delivery. ToneEngine merges AI suggestions
/// with local defaults to produce this struct.
struct VoiceProfile: Codable, Equatable {
    var voiceIdentifier: String?    // BCP-47 or AVSpeechSynthesisVoice identifier
    var rate: Float                 // 0.0–1.0 (AVSpeechUtterance scale)
    var pitch: Float                // 0.5–2.0
    var volume: Float               // 0.0–1.0
    var pauseAfterMs: Int           // Milliseconds of silence appended after utterance

    static let `default` = VoiceProfile(
        voiceIdentifier: nil,
        rate: 0.50,
        pitch: 1.0,
        volume: 1.0,
        pauseAfterMs: 300
    )
}

// MARK: - ToneAnalysis (returned by online AI)

/// Structured direction from the online AI. Never contains rewritten dialogue.
struct ToneAnalysis: Codable {
    var sceneTone: [String]                     // ["tense", "playful"]
    var characterIntent: [String: String]       // ["ALEX": "hiding guilt"]
    var deliveryNotes: [Int: String]?           // lineIndex → note
    var ttsProfiles: [String: VoiceProfile]?    // character → suggested profile

    enum CodingKeys: String, CodingKey {
        case sceneTone = "scene_tone"
        case characterIntent = "character_intent"
        case deliveryNotes = "delivery_notes"
        case ttsProfiles = "tts_profile"
    }
}
