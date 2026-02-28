// NetworkAIService.swift
// ScenePartner — Stub for all online AI features.
//
// This file shows the full design with pseudocode and stub implementations.
// Replace the stub bodies with real API calls in a future iteration.
// Online features NEVER block rehearsal; all calls are async and optional.

import Foundation

// MARK: - Errors

enum AIServiceError: Error {
    case offline
    case rateLimited
    case invalidResponse
    case serverError(Int)
}

// MARK: - NetworkAIService

final class NetworkAIService {

    // MARK: - Config (replace with your real endpoint / key management)

    private let baseURL = URL(string: "https://api.openai.com/v1")!
    private let session: URLSession

    /// Set via Settings — if false, no network calls are ever made.
    var localOnlyMode: Bool = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 1. Find My Place
    //
    // Sends a small context window to the LLM and gets back a line index.
    // Used when the user is lost and wants the partner to resume from the right place.
    //
    // PSEUDOCODE IMPLEMENTATION:
    //
    //   func findMyPlace(
    //       spokenText: String,          // What the user just said (from Apple Speech)
    //       surroundingLines: [Line],    // ±5 lines of script context
    //       scriptTitle: String
    //   ) async throws -> Int {          // Returns matching lineIndex
    //
    //       guard !localOnlyMode else { throw AIServiceError.offline }
    //
    //       let prompt = """
    //       You are a script continuity assistant. Given the script excerpt and the actor's
    //       spoken text, return ONLY a JSON object: {"line_index": <int>}
    //       where line_index is the best matching index in the excerpt.
    //       Excerpt: \(surroundingLines.map { "\($0.index): \($0.text)" }.joined(separator: "\n"))
    //       Actor said: "\(spokenText)"
    //       """
    //
    //       let response = try await callLLM(prompt: prompt, maxTokens: 20)
    //       // Parse {"line_index": N} and return N
    //   }

    func findMyPlace(
        spokenText: String,
        surroundingLines: [Line],
        scriptTitle: String
    ) async throws -> Int {
        guard !localOnlyMode else { throw AIServiceError.offline }
        // STUB — returns first surrounding line index
        try await Task.sleep(nanoseconds: 500_000_000) // simulate latency
        return surroundingLines.first?.index ?? 0
    }

    // MARK: - 2. Tone & Context Analysis
    //
    // Sends scene text (no full script) and receives structured delivery direction.
    // Returned ToneAnalysis is used only by ToneEngine / UI hints — NOT dialogue.
    //
    // PSEUDOCODE IMPLEMENTATION:
    //
    //   func analyzeTone(
    //       scene: Scene,
    //       lines: [Line]
    //   ) async throws -> ToneAnalysis {
    //
    //       guard !localOnlyMode else { throw AIServiceError.offline }
    //
    //       let sceneText = lines.filter { scene.lineIndices.contains($0.index) }
    //                            .map { "\($0.speaker ?? ""): \($0.text)" }
    //                            .joined(separator: "\n")
    //
    //       let systemPrompt = """
    //       You are a script director. Analyze the scene and return ONLY valid JSON matching:
    //       {
    //         "scene_tone": ["label1", "label2"],
    //         "character_intent": {"CHAR": "short intent"},
    //         "delivery_notes": {"<lineIndex>": "note"},
    //         "tts_profile": {"CHAR": {"rate":0.5,"pitch":1.0,"volume":1.0,"pause_after_ms":300}}
    //       }
    //       DO NOT rewrite or add dialogue. Direction only.
    //       """
    //
    //       let response = try await callLLM(systemPrompt: systemPrompt,
    //                                         userPrompt: sceneText, maxTokens: 400)
    //       return try JSONDecoder().decode(ToneAnalysis.self, from: response)
    //   }

    func analyzeTone(scene: Scene, lines: [Line]) async throws -> ToneAnalysis {
        guard !localOnlyMode else { throw AIServiceError.offline }
        try await Task.sleep(nanoseconds: 800_000_000)
        // STUB — returns a generic playful/tense analysis
        return ToneAnalysis(
            sceneTone: ["tense", "intimate"],
            characterIntent: [:],
            deliveryNotes: nil,
            ttsProfiles: nil
        )
    }

    // MARK: - 3. Coaching Feedback
    //
    // After rehearsal completes, send a summary of the run for coaching notes.
    // Returns plain-text feedback (shown in a post-run screen, never during rehearsal).
    //
    // PSEUDOCODE IMPLEMENTATION:
    //
    //   func getCoachingFeedback(
    //       runSummary: RehearsalRunSummary   // duration, lines hit, pauses, etc.
    //   ) async throws -> String {
    //
    //       guard !localOnlyMode else { throw AIServiceError.offline }
    //
    //       let prompt = "Based on this rehearsal summary, give 3 concise director notes: \(runSummary)"
    //       return try await callLLM(prompt: prompt, maxTokens: 200)
    //   }

    func getCoachingFeedback(runSummary: String) async throws -> String {
        guard !localOnlyMode else { throw AIServiceError.offline }
        try await Task.sleep(nanoseconds: 600_000_000)
        // STUB
        return "Great run! Focus on pacing in Scene 2 and let the silences breathe more."
    }

    // MARK: - 4. Improv Partner Line (only when Improv Mode is ON)
    //
    // Returns a single partner ad-lib that is tonally consistent but NOT from the script.
    // Must never be called unless RehearsalState.isImprovModeOn == true.
    //
    // PSEUDOCODE IMPLEMENTATION:
    //
    //   func getImprovLine(
    //       character: String,
    //       precedingLines: [Line],
    //       tone: [String]
    //   ) async throws -> String {
    //
    //       guard !localOnlyMode else { throw AIServiceError.offline }
    //
    //       let context = precedingLines.suffix(4)
    //                          .map { "\($0.speaker ?? ""): \($0.text)" }
    //                          .joined(separator: "\n")
    //       let prompt = """
    //       You are \(character). Continue naturally in 1–2 sentences.
    //       Tone: \(tone.joined(separator: ", ")).
    //       Context:\n\(context)
    //       """
    //       return try await callLLM(prompt: prompt, maxTokens: 60)
    //   }

    func getImprovLine(character: String, precedingLines: [Line], tone: [String]) async throws -> String {
        guard !localOnlyMode else { throw AIServiceError.offline }
        try await Task.sleep(nanoseconds: 400_000_000)
        // STUB
        return "I'm not sure what you mean by that."
    }

    // MARK: - Internal LLM caller (implement with your API of choice)

    // PSEUDOCODE for callLLM:
    //
    //   private func callLLM(
    //       systemPrompt: String = "",
    //       userPrompt: String,
    //       maxTokens: Int
    //   ) async throws -> Data {
    //
    //       var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
    //       request.httpMethod = "POST"
    //       request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    //       request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    //
    //       let body: [String: Any] = [
    //           "model": "gpt-4o-mini",
    //           "max_tokens": maxTokens,
    //           "messages": [
    //               ["role": "system", "content": systemPrompt],
    //               ["role": "user",   "content": userPrompt]
    //           ]
    //       ]
    //       request.httpBody = try JSONSerialization.data(withJSONObject: body)
    //
    //       let (data, response) = try await session.data(for: request)
    //       guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
    //       guard (200..<300).contains(http.statusCode) else {
    //           throw AIServiceError.serverError(http.statusCode)
    //       }
    //       // Extract choices[0].message.content from OpenAI response envelope
    //       return data
    //   }
}
