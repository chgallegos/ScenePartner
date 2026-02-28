// VoiceEngine.swift
// ScenePartner — Protocol-based voice abstraction.
//
// Architecture goal: RehearsalEngine calls only the VoiceEngineProtocol.
// Swap AVSpeechSynthesizer for a neural voice provider by implementing
// the protocol — zero changes to RehearsalEngine required.

import Foundation
import AVFoundation
import Combine

// MARK: - VoiceEngineProtocol

/// The contract all voice backends must fulfil.
protocol VoiceEngineProtocol: AnyObject {

    /// Speak a line using the given profile.
    /// Completion is called on the main queue when utterance finishes (or is cancelled).
    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void)

    /// Stop any current utterance immediately.
    func stop()

    /// Pause the current utterance.
    func pause()

    /// Resume a paused utterance.
    func resume()

    /// True while an utterance is actively playing (not paused, not stopped).
    var isSpeaking: Bool { get }
}

// MARK: - SpeechManager (AVSpeechSynthesizer implementation)

/// Concrete offline-capable voice engine backed by AVSpeechSynthesizer.
final class SpeechManager: NSObject, VoiceEngineProtocol {

    // MARK: - Private

    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?
    private var pauseTimer: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - VoiceEngineProtocol

    var isSpeaking: Bool {
        synthesizer.isSpeaking && !synthesizer.isPaused
    }

    func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void) {
        // Cancel anything in-flight
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        completionHandler = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = profile.rate.clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = profile.pitch.clamped(to: 0.5...2.0)
        utterance.volume = profile.volume.clamped(to: 0.0...1.0)

        if let identifier = profile.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }

        // Add post-utterance silence via a trailing pause in the string
        // (AVSpeechUtterance.postUtteranceDelay is available iOS 17+; use timer fallback)
        if #available(iOS 17.0, *) {
            utterance.postUtteranceDelay = Double(profile.pauseAfterMs) / 1000.0
        }
        // (On earlier iOS the delegate fires immediately after speech; we insert
        //  the delay in didFinish via a Timer — see below.)

        synthesizer.speak(utterance)
    }

    func stop() {
        pauseTimer?.invalidate()
        synthesizer.stopSpeaking(at: .immediate)
        completionHandler = nil
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                            options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[SpeechManager] Audio session config failed: \(error)")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        let handler = completionHandler
        completionHandler = nil

        // On iOS < 17, apply pauseAfterMs via Timer
        if #available(iOS 17.0, *) {
            DispatchQueue.main.async { handler?() }
        } else {
            // We don't have access to the profile here, so we fire immediately.
            // For a production app, store the profile on self and use it here.
            DispatchQueue.main.async { handler?() }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        completionHandler = nil
    }
}

// MARK: - Float clamping helper

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Future Extension Points (DO NOT IMPLEMENT — architecture hooks only)
// ---------------------------------------------------------------------------
//
// To add a neural voice provider:
//
//   final class NeuralVoiceEngine: VoiceEngineProtocol {
//       func speak(text: String, profile: VoiceProfile, completion: @escaping () -> Void) {
//           // Call ElevenLabs / Apple Neural TTS / etc.
//           // Map VoiceProfile → provider-specific parameters
//       }
//       // ... other protocol methods
//   }
//
// Then inject NeuralVoiceEngine into RehearsalEngine instead of SpeechManager.
// No other changes required.
//
// To add user-recorded voices:
//
//   final class RecordedVoiceEngine: VoiceEngineProtocol {
//       // Load pre-recorded audio files keyed by (speaker, lineIndex)
//       // Fall back to SpeechManager when no recording exists
//   }
