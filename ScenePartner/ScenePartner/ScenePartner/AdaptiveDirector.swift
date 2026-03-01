// AdaptiveDirector.swift
// ScenePartner — Listens to the scene as it develops and evolves the AI character's
// emotional direction in real time using an LLM.
//
// How it works:
// 1. Tracks the last N exchanges (user lines + partner lines)
// 2. Every few exchanges, asks the LLM: "given what just happened, how should the
//    partner be feeling and delivering their next lines?"
// 3. Updates the ElevenLabsVoiceEngine's direction silently — no UI disruption
// 4. Works only when online. Falls back to static direction when offline.

import Foundation

@MainActor
final class AdaptiveDirector: ObservableObject {

    // MARK: - Published State
    @Published private(set) var currentDirection: CharacterDirection
    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastAdaptationNote: String = ""  // shown in UI as subtle hint

    // MARK: - Config
    private let characterName: String
    private let apiKey: String             // OpenAI key — stored in settings
    private let updateEveryNExchanges = 2  // Re-analyze after every 2 exchanges

    // MARK: - State
    private var exchangeCount = 0
    private var recentExchanges: [(speaker: String, text: String)] = []
    private let maxContext = 8  // Keep last 8 lines for context

    init(characterName: String, initialDirection: CharacterDirection, openAIKey: String) {
        self.characterName = characterName
        self.currentDirection = initialDirection
        self.apiKey = openAIKey
    }

    // MARK: - Track Scene Progress

    /// Call this every time a line is spoken (by anyone)
    func recordLine(speaker: String, text: String) {
        recentExchanges.append((speaker: speaker, text: text))
        if recentExchanges.count > maxContext {
            recentExchanges.removeFirst()
        }

        // Count exchanges (user + partner = 1 exchange)
        if speaker != characterName {
            exchangeCount += 1
            if exchangeCount % updateEveryNExchanges == 0 {
                Task { await analyzeAndAdapt() }
            }
        }
    }

    // MARK: - LLM Analysis

    private func analyzeAndAdapt() async {
        guard !apiKey.isEmpty else { return }
        guard recentExchanges.count >= 2 else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let newDirection = try await fetchAdaptedDirection()
            currentDirection = newDirection
            print("[AdaptiveDirector] 🎭 Direction updated for \(characterName): \(newDirection.emotionalState)")
        } catch {
            print("[AdaptiveDirector] ⚠️ Analysis failed: \(error) — keeping current direction")
        }
    }

    private func fetchAdaptedDirection() async throws -> CharacterDirection {
        let context = recentExchanges
            .map { "\($0.speaker.uppercased()): \($0.text)" }
            .joined(separator: "\n")

        let toneOptions = TonePreset.allCases.map { $0.rawValue }.joined(separator: ", ")

        let prompt = """
        You are a skilled acting coach analyzing a live scene rehearsal.

        Character you are directing: \(characterName)
        Their original direction: \(currentDirection.emotionalState), objective: \(currentDirection.objective)

        Recent scene exchanges:
        \(context)

        Based on how this scene is developing, update the emotional direction for \(characterName)'s NEXT lines.
        React to what was just said to them. The direction should feel like a natural response to the scene.

        Respond with ONLY a JSON object — no explanation, no markdown:
        {
          "emotional_state": "2-4 word description of how they're feeling right now",
          "objective": "what they want in this moment (may have shifted)",
          "tones": ["tone1", "tone2"],
          "adaptation_note": "one sentence explaining the shift for the actor"
        }

        Available tones: \(toneOptions)
        Pick 1-3 tones that best match the current emotional beat.
        """

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8  // Fast — don't block the scene

        let body: [String: Any] = [
            "model": "gpt-4o-mini",  // Fast + cheap for real-time use
            "max_tokens": 120,
            "temperature": 0.7,
            "messages": [
                ["role": "system", "content": "You are a concise acting coach. Respond only with valid JSON."],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw DirectorError.apiError
        }

        // Parse OpenAI response envelope
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DirectorError.parseError
        }

        // Parse the inner JSON
        let cleanContent = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let innerData = cleanContent.data(using: .utf8),
              let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] else {
            throw DirectorError.parseError
        }

        let newState = inner["emotional_state"] as? String ?? currentDirection.emotionalState
        let newObjective = inner["objective"] as? String ?? currentDirection.objective
        let newTones = inner["tones"] as? [String] ?? currentDirection.tone
        let note = inner["adaptation_note"] as? String ?? ""

        await MainActor.run { self.lastAdaptationNote = note }

        return CharacterDirection(
            characterName: characterName,
            emotionalState: newState,
            objective: newObjective,
            tone: newTones,
            additionalNotes: currentDirection.additionalNotes
        )
    }

    enum DirectorError: Error { case apiError, parseError }
}
