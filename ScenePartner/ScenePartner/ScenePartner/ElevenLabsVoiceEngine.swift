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

    // Direction context injected before speaking
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
            fallback.speak(text: text, profile: profile, completion: completion)
            return
        }

        Task {
            do {
                let audioData = try await fetchAudio(text: text, profile: profile)
                await MainActor.run { self.playAudio(data: audioData, completion: completion) }
            } catch {
                print("[ElevenLabs] Error: \(error) — using fallback")
                await MainActor.run { self.fallback.speak(text: text, profile: profile, completion: completion) }
            }
        }
    }

    func stop()   { player?.pause(); player = nil; isPlaying = false; fallback.stop(); completionHandler = nil }
    func pause()  { player?.pause(); fallback.pause() }
    func resume() { player?.play(); fallback.resume() }

    // MARK: - API Call

    private func fetchAudio(text: String, profile: VoiceProfile) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        // Map emotional direction to voice stability
        // More emotional/tense = lower stability = more expressive variation
        let stability = stabilityFromProfile(profile)
        let style = styleFromDirection()

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
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VoiceError.apiError
        }
        return data
    }

    /// More expressive tones = lower stability (more human variation)
    private func stabilityFromProfile(_ profile: VoiceProfile) -> Double {
        let expressiveTones = ["angry", "desperate", "fearful", "urgent", "defiant"]
        let calmTones = ["intimate", "mysterious", "sad", "vulnerable"]

        // Check current scene direction for tone cues
        let allTones = sceneDirection.characterDirections.values.flatMap { $0.tone }

        if allTones.contains(where: { expressiveTones.contains($0) }) {
            return 0.30  // Very expressive
        } else if allTones.contains(where: { calmTones.contains($0) }) {
            return 0.55  // Controlled, subtle
        }
        return 0.45  // Default — natural variation
    }

    /// Style exaggeration based on emotional intensity
    private func styleFromDirection() -> Double {
        let highIntensity = ["angry", "desperate", "urgent", "defiant", "fearful"]
        let allTones = sceneDirection.characterDirections.values.flatMap { $0.tone }
        if allTones.contains(where: { highIntensity.contains($0) }) { return 0.55 }
        return 0.30
    }

    // MARK: - Playback

    private func playAudio(data: Data, completion: @escaping () -> Void) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp3")
        do { try data.write(to: tmpURL) } catch {
            fallback.speak(text: "", profile: .default, completion: completion)
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])

        playerItem = AVPlayerItem(url: tmpURL)
        player = AVPlayer(playerItem: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinish),
                                               name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        player?.play()
    }

    @objc private func playerDidFinish() {
        isPlaying = false
        let handler = completionHandler
        completionHandler = nil
        DispatchQueue.main.async { handler?() }
    }

    enum VoiceError: Error { case apiError }
}
