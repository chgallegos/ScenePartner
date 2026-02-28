// ElevenLabsVoiceEngine.swift
// ScenePartner — Neural voice engine using ElevenLabs API.
// Falls back to AVSpeechSynthesizer when offline or API unavailable.

import Foundation
import AVFoundation

final class ElevenLabsVoiceEngine: NSObject, VoiceEngineProtocol, @unchecked Sendable {

    // MARK: - Config
    // Get your API key at elevenlabs.io — store in Settings, never hardcode
    private let apiKey: String
    
    // Default voice IDs from ElevenLabs — swap these for any voice you want
    // Browse voices at elevenlabs.io/voice-library
    static let defaultVoiceID = "onwK4e9ZLuTAKqWW03F9"  // Daniel — deep, clear, natural
    static let femaleVoiceID  = "EXAVITQu4vr4xnSDxMaL"  // Bella — warm, natural
    
    private let voiceID: String
    private let fallback = SpeechManager()
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var completionHandler: (() -> Void)?
    private var isPlaying = false
    private var useFallback = false

    var isSpeaking: Bool { isPlaying }

    init(apiKey: String, voiceID: String = ElevenLabsVoiceEngine.defaultVoiceID) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        super.init()
    }

    // MARK: - VoiceEngineProtocol

    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void) {
        completionHandler = completion
        isPlaying = true

        if apiKey.isEmpty {
            // No API key — use fallback silently
            useFallbackSpeech(text: text, profile: profile, completion: completion)
            return
        }

        Task {
            do {
                let audioData = try await fetchAudio(text: text, profile: profile)
                await MainActor.run { self.playAudio(data: audioData, completion: completion) }
            } catch {
                print("[ElevenLabs] API error: \(error) — falling back to AVSpeech")
                await MainActor.run { self.useFallbackSpeech(text: text, profile: profile, completion: completion) }
            }
        }
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        fallback.stop()
        completionHandler = nil
    }

    func pause() {
        player?.pause()
        fallback.pause()
    }

    func resume() {
        player?.play()
        fallback.resume()
    }

    // MARK: - ElevenLabs API

    private func fetchAudio(text: String, profile: VoiceProfile) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        // Map our VoiceProfile to ElevenLabs voice settings
        // stability: 0.3-0.5 = more expressive/variable, 0.7-1.0 = more consistent
        // similarity_boost: how closely it follows the original voice
        let stability = Double(1.0 - (profile.rate - 0.3))  // faster speech = less stable = more expressive
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",  // fastest, lowest latency
            "voice_settings": [
                "stability": max(0.3, min(0.9, stability)),
                "similarity_boost": 0.75,
                "style": 0.35,              // some style exaggeration for drama
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

    // MARK: - Playback

    private func playAudio(data: Data, completion: @escaping () -> Void) {
        // Write to temp file — AVPlayer needs a URL
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp3")
        do {
            try data.write(to: tmpURL)
        } catch {
            useFallbackSpeech(text: "", profile: .default, completion: completion)
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                          options: [.duckOthers])

        playerItem = AVPlayerItem(url: tmpURL)
        player = AVPlayer(playerItem: playerItem)

        // Observe when playback ends
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        player?.play()
    }

    @objc private func playerDidFinish() {
        isPlaying = false
        let handler = completionHandler
        completionHandler = nil
        DispatchQueue.main.async { handler?() }
    }

    private func useFallbackSpeech(text: String, profile: VoiceProfile, completion: @escaping () -> Void) {
        isPlaying = false
        if text.isEmpty { completion(); return }
        fallback.speak(text: text, profile: profile, completion: completion)
    }

    enum VoiceError: Error { case apiError }
}
