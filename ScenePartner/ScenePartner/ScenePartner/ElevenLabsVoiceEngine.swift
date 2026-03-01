// ElevenLabsVoiceEngine.swift
import Foundation
import AVFoundation

final class ElevenLabsVoiceEngine: NSObject, VoiceEngineProtocol, @unchecked Sendable {

    private let apiKey: String
    private let voiceID: String
    private let fallback = SpeechManager()
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var completionHandler: (() -> Void)?
    private var isPlaying = false

    var sceneDirection: SceneDirection = .empty

    // Expressive model — much better emotional range than turbo
    // eleven_multilingual_v2 = best quality/emotion
    // eleven_turbo_v2_5 = fastest but least expressive
    private let model = "eleven_multilingual_v2"

    static let defaultVoiceID = "onwK4e9ZLuTAKqWW03F9"  // Daniel
    static let femaleVoiceID  = "EXAVITQu4vr4xnSDxMaL"  // Bella

    // High-expressiveness voices worth trying:
    // "pNInz6obpgDQGcFmaJgB" — Adam (deep, dramatic)
    // "VR6AewLTigWG4xSOukaG" — Arnold (strong, authoritative)
    // "ErXwobaYiN019PkySvjV" — Antoni (warm, natural)
    // "MF3mGyEYCl7XYWbV9V6O" — Elli (emotional, expressive)
    // "TxGEqnHWrfWFTfGW9XjX" — Josh (deep, warm)

    var isSpeaking: Bool { isPlaying }

    init(apiKey: String, voiceID: String = ElevenLabsVoiceEngine.defaultVoiceID) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        super.init()
    }

    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void) {
        completionHandler = completion
        isPlaying = true

        if apiKey.isEmpty {
            print("[ElevenLabs] ⚠️ No API key — using AVSpeech fallback")
            fallback.speak(text: text, profile: profile, completion: completion)
            return
        }

        Task {
            do {
                // Inject emotional context directly into the text via prompt engineering
                let emotionalText = injectEmotionalContext(into: text)
                let audioData = try await fetchAudio(text: emotionalText, profile: profile)
                await MainActor.run { self.playAudio(data: audioData, completion: completion) }
            } catch {
                print("[ElevenLabs] ❌ Error: \(error) — using fallback")
                await MainActor.run {
                    self.isPlaying = false
                    self.fallback.speak(text: text, profile: profile, completion: completion)
                }
            }
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self,
            name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        player?.pause(); player = nil; playerItem = nil
        isPlaying = false; fallback.stop(); completionHandler = nil
    }

    func pause()  { player?.pause(); fallback.pause() }
    func resume() { player?.play(); fallback.resume() }

    // MARK: - Emotional Text Injection
    // This is the key technique: we wrap the text with emotional stage direction
    // that the model reads as performance instruction

    // MARK: - Inline Emotion Injection
    // eleven_multilingual_v2 responds to acting notes placed BEFORE the line in brackets.
    // e.g. "[whispering, desperate] I had to." sounds fundamentally different from just "I had to."
    // We build a specific, actor-friendly note from the direction the user set.

    private func injectEmotionalContext(into text: String) -> String {
        let note = buildActingNote()
        guard !note.isEmpty else {
            print("[ElevenLabs] 🎭 No direction — speaking as written")
            return text
        }

        let injected = "[\(note)] \(text)"
        print("""
        [ElevenLabs] 🎭 Injecting acting note:
          Note: [\(note)]
          Line: "\(text.prefix(60))"
          Full: "\(injected.prefix(80))"
          Model: \(model) | stability:\(stabilityFromDirection()) style:\(styleFromDirection()) speed:\(speedFromDirection())
        """)
        return injected
    }

    private func buildActingNote() -> String {
        let tones = allTones()
        let state = allEmotionalStates()
        let objective = allObjectives()

        var parts: [String] = []

        // 1. Physical/vocal delivery cue from tone
        if let deliveryCue = deliveryCue(from: tones) {
            parts.append(deliveryCue)
        }

        // 2. Emotional state (most important — use as-is if set)
        if !state.isEmpty {
            parts.append(state)
        }

        // 3. Subtext / want
        if !objective.isEmpty {
            parts.append("trying to \(objective)")
        }

        return parts.joined(separator: ", ")
    }

    // Maps tone tags to specific vocal/physical acting instructions
    // These are phrased the way a director would give notes to an actor
    private func deliveryCue(from tones: [String]) -> String? {
        // Priority order — most specific wins
        if tones.contains("desperate")   { return "voice breaking, barely holding it together" }
        if tones.contains("angry")       { return "jaw tight, controlled fury" }
        if tones.contains("fearful")     { return "voice trembling, barely above a whisper" }
        if tones.contains("vulnerable")  { return "raw, unguarded, voice soft" }
        if tones.contains("intimate")    { return "low and close, speaking only to this person" }
        if tones.contains("defiant")     { return "chin up, voice steady and hard" }
        if tones.contains("bitter")      { return "cold, clipped, each word deliberate" }
        if tones.contains("sad")         { return "heavy, slow, the weight of it showing" }
        if tones.contains("hopeful")     { return "light, reaching, almost afraid to say it" }
        if tones.contains("loving")      { return "warm, unhurried, meaning every word" }
        if tones.contains("tense")       { return "guarded, measuring each word carefully" }
        if tones.contains("urgent")      { return "rushed, no time, has to get this out" }
        if tones.contains("mysterious")  { return "quiet and deliberate, revealing nothing" }
        if tones.contains("playful")     { return "light, almost laughing, enjoying this" }
        if tones.contains("comedic")     { return "dry delivery, barely containing amusement" }
        return nil
    }

    // MARK: - API Call

    private func fetchAudio(text: String, profile: VoiceProfile) async throws -> Data {
        let stability = stabilityFromDirection()
        let style = styleFromDirection()
        let speed = speedFromDirection()

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "text": text,
            "model_id": model,
            "voice_settings": [
                "stability": stability,
                "similarity_boost": 0.80,
                "style": style,
                "use_speaker_boost": true,
                "speed": speed
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VoiceError.apiError }

        print("[ElevenLabs] ✅ HTTP \(http.statusCode), \(data.count) bytes | stability:\(stability) style:\(style) speed:\(speed)")

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[ElevenLabs] ❌ Error: \(body)")
            throw VoiceError.apiError
        }
        return data
    }

    // MARK: - Direction → Parameters

    private func allTones() -> [String] {
        sceneDirection.characterDirections.values.flatMap { $0.tone }
    }
    private func allEmotionalStates() -> String {
        sceneDirection.characterDirections.values.map { $0.emotionalState }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    private func allObjectives() -> String {
        sceneDirection.characterDirections.values.map { $0.objective }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func stabilityFromDirection() -> Double {
        let tones = allTones()
        // Lower = more variable/expressive, Higher = more consistent/controlled
        if tones.contains(where: { ["angry","desperate","fearful","defiant","bitter"].contains($0) }) { return 0.20 }
        if tones.contains(where: { ["tense","urgent","comedic"].contains($0) }) { return 0.30 }
        if tones.contains(where: { ["intimate","vulnerable","loving","hopeful"].contains($0) }) { return 0.45 }
        if tones.contains(where: { ["sad","mysterious"].contains($0) }) { return 0.50 }
        return 0.38  // Default: slightly expressive
    }

    private func styleFromDirection() -> Double {
        let tones = allTones()
        // Higher = more exaggerated/theatrical performance style
        if tones.contains(where: { ["angry","desperate","defiant","comedic"].contains($0) }) { return 0.75 }
        if tones.contains(where: { ["tense","urgent","fearful","bitter"].contains($0) }) { return 0.60 }
        if tones.contains(where: { ["intimate","vulnerable","loving","sad"].contains($0) }) { return 0.25 }
        if tones.contains(where: { ["mysterious","hopeful"].contains($0) }) { return 0.35 }
        return 0.45
    }

    private func speedFromDirection() -> Double {
        let tones = allTones()
        // Speed affects pacing — urgent/angry = faster, sad/intimate = slower
        if tones.contains(where: { ["urgent","angry","defiant","comedic"].contains($0) }) { return 1.10 }
        if tones.contains(where: { ["desperate","fearful","tense"].contains($0) }) { return 1.05 }
        if tones.contains(where: { ["sad","intimate","mysterious","vulnerable"].contains($0) }) { return 0.88 }
        if tones.contains(where: { ["loving","hopeful"].contains($0) }) { return 0.92 }
        return 1.0
    }

    // MARK: - Playback

    private func playAudio(data: Data, completion: @escaping () -> Void) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp3")
        do {
            try data.write(to: tmpURL)
        } catch {
            print("[ElevenLabs] ❌ Failed to write: \(error)")
            isPlaying = false; completion(); return
        }

        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers])

        playerItem = AVPlayerItem(url: tmpURL)
        player = AVPlayer(playerItem: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        player?.play()
    }

    @objc private func playerDidFinish() {
        print("[ElevenLabs] ✅ Playback finished")
        isPlaying = false
        NotificationCenter.default.removeObserver(self,
            name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        player = nil; playerItem = nil
        let handler = completionHandler
        completionHandler = nil
        DispatchQueue.main.async { handler?() }
    }

    enum VoiceError: Error { case apiError }
}
