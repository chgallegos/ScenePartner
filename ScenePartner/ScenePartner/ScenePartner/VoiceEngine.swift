// VoiceEngine.swift
// ScenePartner — Protocol-based voice abstraction.

import Foundation
import AVFoundation

// MARK: - VoiceEngineProtocol

protocol VoiceEngineProtocol: AnyObject {
    func speak(text: String, profile: VoiceProfile, completion: @escaping @Sendable () -> Void)
    func stop()
    func pause()
    func resume()
    var isSpeaking: Bool { get }
}

// MARK: - SpeechManager

final class SpeechManager: NSObject, VoiceEngineProtocol {

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

    func speak(text: String, profile: VoiceProfile, completion: @escaping @Sendable () -> Void) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        completionHandler = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = profile.rate.clamped(
            to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = profile.pitch.clamped(to: 0.5...2.0)
        utterance.volume = profile.volume.clamped(to: 0.0...1.0)

        if let identifier = profile.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
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

    func pause() { synthesizer.pauseSpeaking(at: .word) }
    func resume() { synthesizer.continueSpeaking() }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - Delegate

extension SpeechManager: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.completionHandler?()
            self?.completionHandler = nil
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        completionHandler = nil
    }
}

// MARK: - Helpers

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
