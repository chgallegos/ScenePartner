// CharacterDirection.swift
// ScenePartner — Per-character emotional direction that shapes how the AI delivers lines.

import Foundation

// MARK: - Direction Models

struct CharacterDirection: Codable, Equatable {
    var characterName: String
    var emotionalState: String       // e.g. "desperate, hiding guilt"
    var objective: String            // e.g. "convince Alex to stay"
    var tone: [String]               // e.g. ["tense", "intimate"]
    var additionalNotes: String      // director's free-form notes

    static func empty(for character: String) -> CharacterDirection {
        CharacterDirection(
            characterName: character,
            emotionalState: "",
            objective: "",
            tone: [],
            additionalNotes: ""
        )
    }
}

struct SceneDirection: Codable, Equatable {
    var sceneContext: String                          // What's happening in this scene
    var characterDirections: [String: CharacterDirection]  // keyed by character name

    static let empty = SceneDirection(sceneContext: "", characterDirections: [:])
}

// MARK: - Preset Tones

enum TonePreset: String, CaseIterable, Identifiable {
    case tense, playful, intimate, angry, sad, comedic, mysterious, urgent,
         desperate, hopeful, bitter, loving, fearful, defiant, vulnerable

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var emoji: String {
        switch self {
        case .tense: return "😤"
        case .playful: return "😄"
        case .intimate: return "🥰"
        case .angry: return "😠"
        case .sad: return "😢"
        case .comedic: return "😂"
        case .mysterious: return "🤫"
        case .urgent: return "⚡️"
        case .desperate: return "😰"
        case .hopeful: return "🌟"
        case .bitter: return "😒"
        case .loving: return "❤️"
        case .fearful: return "😨"
        case .defiant: return "😤"
        case .vulnerable: return "🫂"
        }
    }
}
