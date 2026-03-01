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

    // eleven_multilingual_v2 = best emotional range
    private let model = "eleven_multilingual_v2"

    static let defaultVoiceID = "onwK4e9ZLuTAKqWW03F9"  // Daniel
    static let femaleVoiceID  = "EXAVITQu4vr4xnSDxMaL"  // Bella

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
            fallback.speak(text: text, profile: profile, completion: completion)
            return
        }

        Task {
            do {
                let audioData = try await fetchAudio(text: text, profile: profile)
                await MainActor.run { self.playAudio(data: audioData, completion: completion) }
            } catch {
                print("[ElevenLabs] ❌ \(error) — using fallback")
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

    // MARK: - API

    private func fetchAudio(text: String, profile: VoiceProfile) async throws -> Data {
        let stability = stabilityFromDirection()
        let style = styleFromDirection()
        let speed = speedFromDirection()

        // Build acting note — sent as context, NOT as spoken text
        let actingNote = buildActingNote()

        print("""
        [ElevenLabs] 🎭
          Acting note (not spoken): \(actingNote.isEmpty ? "none" : actingNote)
          Line: "\(text.prefix(60))"
          stability:\(stability) style:\(style) speed:\(speed)
        """)

        // Use the /v1/text-to-speech endpoint with pronunciation context
        // The acting note goes in `previous_text` — model uses it as context
        // but NEVER speaks it. This is the correct ElevenLabs approach.
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        var body: [String: Any] = [
            "text": text,  // ONLY the actual dialogue — never the acting note
            "model_id": model,
            "voice_settings": [
                "stability": stability,
                "similarity_boost": 0.80,
                "style": style,
                "use_speaker_boost": true,
                "speed": speed
            ]
        ]

        // previous_text gives the model context without being spoken
        // We use it to carry the emotional direction
        if !actingNote.isEmpty {
            body["previous_text"] = actingNote
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VoiceError.apiError }

        print("[ElevenLabs] ✅ HTTP \(http.statusCode), \(data.count) bytes")

        guard (200..<300).contains(http.statusCode) else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            print("[ElevenLabs] ❌ Error: \(errBody)")
            throw VoiceError.apiError
        }
        return data
    }

    // MARK: - Acting Note Builder

    private func buildActingNote() -> String {
        let tones = allTones()
        let state = allEmotionalStates()
        let objective = allObjectives()

        var parts: [String] = []

        if let cue = deliveryCue(from: tones) { parts.append(cue) }
        if !state.isEmpty { parts.append(state) }
        if !objective.isEmpty { parts.append("trying to \(objective)") }

        return parts.joined(separator: ", ")
    }

    private func deliveryCue(from tones: [String]) -> String? {
        if tones.contains("desperate")  { return "voice breaking, barely holding it together" }
        if tones.contains("angry")      { return "jaw tight, controlled fury" }
        if tones.contains("fearful")    { return "voice trembling, barely above a whisper" }
        if tones.contains("vulnerable") { return "raw, unguarded, voice soft" }
        if tones.contains("intimate")   { return "low and close, speaking only to this person" }
        if tones.contains("defiant")    { return "chin up, voice steady and hard" }
        if tones.contains("bitter")     { return "cold, clipped, each word deliberate" }
        if tones.contains("sad")        { return "heavy, slow, the weight of it showing" }
        if tones.contains("hopeful")    { return "light, reaching, almost afraid to say it" }
        if tones.contains("loving")     { return "warm, unhurried, meaning every word" }
        if tones.contains("tense")      { return "guarded, measuring each word carefully" }
        if tones.contains("urgent")     { return "rushed, no time, has to get this out" }
        if tones.contains("mysterious") { return "quiet and deliberate, revealing nothing" }
        if tones.contains("playful")    { return "light, almost laughing, enjoying this" }
        if tones.contains("comedic")    { return "dry delivery, barely containing amusement" }
        return nil
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
        let t = allTones()
        if t.contains(where: { ["angry","desperate","fearful","defiant","bitter"].contains($0) }) { return 0.20 }
        if t.contains(where: { ["tense","urgent","comedic"].contains($0) }) { return 0.30 }
        if t.contains(where: { ["intimate","vulnerable","loving","hopeful"].contains($0) }) { return 0.45 }
        if t.contains(where: { ["sad","mysterious"].contains($0) }) { return 0.50 }
        return 0.38
    }

    private func styleFromDirection() -> Double {
        let t = allTones()
        if t.contains(where: { ["angry","desperate","defiant","comedic"].contains($0) }) { return 0.75 }
        if t.contains(where: { ["tense","urgent","fearful","bitter"].contains($0) }) { return 0.60 }
        if t.contains(where: { ["intimate","vulnerable","loving","sad"].contains($0) }) { return 0.25 }
        if t.contains(where: { ["mysterious","hopeful"].contains($0) }) { return 0.35 }
        return 0.45
    }

    private func speedFromDirection() -> Double {
        let t = allTones()
        if t.contains(where: { ["urgent","angry","defiant","comedic"].contains($0) }) { return 1.10 }
        if t.contains(where: { ["desperate","fearful","tense"].contains($0) }) { return 1.05 }
        if t.contains(where: { ["sad","intimate","mysterious","vulnerable"].contains($0) }) { return 0.88 }
        if t.contains(where: { ["loving","hopeful"].contains($0) }) { return 0.92 }
        return 1.0
    }

    // MARK: - Playback

    private func playAudio(data: Data, completion: @escaping () -> Void) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp3")
        do { try data.write(to: tmpURL) } catch {
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
