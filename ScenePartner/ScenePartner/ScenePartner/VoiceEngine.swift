// VoiceEngine.swift
import Foundation
import AVFoundation

// MARK: - Protocol

protocol VoiceEngineProtocol: AnyObject {
    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void)
    func stop()
    func pause()
    func resume()
    var isSpeaking: Bool { get }
}

// MARK: - SpeechManager
// @unchecked Sendable: we manually ensure thread safety via DispatchQueue.main

final class SpeechManager: NSObject, VoiceEngineProtocol, @unchecked Sendable {

    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking && !synthesizer.isPaused
    }

    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        completionHandler = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = profile.rate.clamped(
            to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = profile.pitch.clamped(to: 0.5...2.0)
        utterance.volume = profile.volume.clamped(to: 0.0...1.0)

        if let id = profile.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }
        if #available(iOS 17.0, *) {
            utterance.postUtteranceDelay = Double(profile.pauseAfterMs) / 1000.0
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        completionHandler = nil
    }

    func pause()  { synthesizer.pauseSpeaking(at: .word) }
    func resume() { synthesizer.continueSpeaking() }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.completionHandler?()
            self?.completionHandler = nil
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.completionHandler = nil }
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
