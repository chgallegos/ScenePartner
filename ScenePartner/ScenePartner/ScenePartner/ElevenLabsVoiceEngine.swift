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
            print("[ElevenLabs] ⚠️ No API key — using AVSpeech fallback")
            fallback.speak(text: text, profile: profile, completion: completion)
            return
        }

        Task {
            do {
                let audioData = try await fetchAudio(text: text, profile: profile)
                await MainActor.run { self.playAudio(data: audioData, completion: completion) }
            } catch {
                print("[ElevenLabs] ❌ Error: \(error) — using AVSpeech fallback")
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
        player?.pause()
        player = nil
        playerItem = nil
        isPlaying = false
        fallback.stop()
        completionHandler = nil
    }
    func pause()  { player?.pause(); fallback.pause() }
    func resume() { player?.play(); fallback.resume() }

    // MARK: - API

    private func fetchAudio(text: String, profile: VoiceProfile) async throws -> Data {
        let stability = stabilityFromDirection()
        let style = styleFromDirection()

        print("""
        [ElevenLabs] 🎭 Sending to API:
          text: "\(text.prefix(60))..."
          voiceID: \(voiceID)
          stability: \(stability)
          style: \(style)
          tones: \(allTones())
          emotional state: \(allEmotionalStates())
          objective: \(allObjectives())
        """)

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": stability,
                "similarity_boost": 0.75,
                "style": style,
                "use_speaker_boost": true
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VoiceError.apiError }

        print("[ElevenLabs] ✅ Response: HTTP \(http.statusCode), \(data.count) bytes")

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("[ElevenLabs] ❌ API error body: \(body)")
            throw VoiceError.apiError
        }
        return data
    }

    // MARK: - Direction → Voice Parameters

    private func allTones() -> [String] {
        sceneDirection.characterDirections.values.flatMap { $0.tone }
    }

    private func allEmotionalStates() -> String {
        sceneDirection.characterDirections.values
            .map { $0.emotionalState }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func allObjectives() -> String {
        sceneDirection.characterDirections.values
            .map { $0.objective }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func stabilityFromDirection() -> Double {
        let tones = allTones()
        let expressive = ["angry", "desperate", "fearful", "urgent", "defiant", "bitter"]
        let calm = ["intimate", "mysterious", "sad", "vulnerable", "loving"]
        if tones.contains(where: { expressive.contains($0) }) { return 0.28 }
        if tones.contains(where: { calm.contains($0) }) { return 0.55 }
        return 0.42
    }

    private func styleFromDirection() -> Double {
        let tones = allTones()
        let highIntensity = ["angry", "desperate", "urgent", "defiant", "fearful", "tense"]
        let lowIntensity = ["intimate", "sad", "mysterious", "vulnerable"]
        if tones.contains(where: { highIntensity.contains($0) }) { return 0.60 }
        if tones.contains(where: { lowIntensity.contains($0) }) { return 0.15 }
        return 0.30
    }

    // MARK: - Playback

    private func playAudio(data: Data, completion: @escaping () -> Void) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp3")
        do {
            try data.write(to: tmpURL)
            print("[ElevenLabs] 🔊 Playing audio from: \(tmpURL.lastPathComponent)")
        } catch {
            print("[ElevenLabs] ❌ Failed to write audio file: \(error)")
            isPlaying = false
            completion()
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers])

        playerItem = AVPlayerItem(url: tmpURL)
        player = AVPlayer(playerItem: playerItem)
        NotificationCenter.default.addObserver(
            self, selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        player?.play()
    }

    @objc private func playerDidFinish() {
        print("[ElevenLabs] ✅ Playback finished")
        isPlaying = false
        // Remove observer BEFORE calling completion to avoid re-entrancy
        NotificationCenter.default.removeObserver(self,
            name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        player = nil
        playerItem = nil
        let handler = completionHandler
        completionHandler = nil
        DispatchQueue.main.async { handler?() }
    }

    enum VoiceError: Error { case apiError }
}
