// ToneEngine.swift
// ScenePartner — Maps tone labels → VoiceProfile adjustments.
//               Merges AI-suggested profiles with local defaults.
//               Works 100% offline with built-in presets.

import Foundation

final class ToneEngine {

    // MARK: - Tone → VoiceProfile Presets (offline fallback)

    /// Adjustments applied on top of VoiceProfile.default for each tone tag.
    private static let toneAdjustments: [String: VoiceProfile] = [
        "tense": VoiceProfile(voiceIdentifier: nil, rate: 0.55, pitch: 1.1, volume: 1.0, pauseAfterMs: 200),
        "playful": VoiceProfile(voiceIdentifier: nil, rate: 0.58, pitch: 1.2, volume: 0.9, pauseAfterMs: 250),
        "intimate": VoiceProfile(voiceIdentifier: nil, rate: 0.42, pitch: 0.95, volume: 0.75, pauseAfterMs: 500),
        "angry": VoiceProfile(voiceIdentifier: nil, rate: 0.60, pitch: 1.15, volume: 1.0, pauseAfterMs: 150),
        "sad": VoiceProfile(voiceIdentifier: nil, rate: 0.38, pitch: 0.85, volume: 0.7, pauseAfterMs: 600),
        "comedic": VoiceProfile(voiceIdentifier: nil, rate: 0.62, pitch: 1.25, volume: 0.95, pauseAfterMs: 200),
        "mysterious": VoiceProfile(voiceIdentifier: nil, rate: 0.40, pitch: 0.90, volume: 0.65, pauseAfterMs: 700),
        "urgent": VoiceProfile(voiceIdentifier: nil, rate: 0.65, pitch: 1.1, volume: 1.0, pauseAfterMs: 100),
    ]

    // MARK: - Public API

    /// Return a VoiceProfile for a given character, merging:
    ///   1. Base default
    ///   2. Scene tone adjustments (averaged if multiple tones)
    ///   3. AI-suggested profile for this character (if available)
    func profile(
        for character: String,
        sceneTones: [String],
        analysis: ToneAnalysis?
    ) -> VoiceProfile {
        var base = VoiceProfile.default

        // Apply tone adjustments (average across active tones)
        let matchingTones = sceneTones.compactMap { ToneEngine.toneAdjustments[$0.lowercased()] }
        if !matchingTones.isEmpty {
            base = average(matchingTones, over: base)
        }

        // Override with AI suggestion if present
        if let aiProfile = analysis?.ttsProfiles?[character.uppercased()] {
            base = merge(base: base, override: aiProfile)
        }

        return base
    }

    /// Merge AI delivery notes onto base profiles.
    /// Returns a map of lineIndex → annotation string for the UI.
    func deliveryNotes(from analysis: ToneAnalysis?) -> [Int: String] {
        return analysis?.deliveryNotes ?? [:]
    }

    // MARK: - Helpers

    private func average(_ profiles: [VoiceProfile], over base: VoiceProfile) -> VoiceProfile {
        guard !profiles.isEmpty else { return base }
        let n = Float(profiles.count)
        let rate = profiles.map(\.rate).reduce(0, +) / n
        let pitch = profiles.map(\.pitch).reduce(0, +) / n
        let volume = profiles.map(\.volume).reduce(0, +) / n
        let pause = Int(profiles.map { Float($0.pauseAfterMs) }.reduce(0, +) / n)
        return VoiceProfile(voiceIdentifier: base.voiceIdentifier,
                            rate: rate, pitch: pitch, volume: volume,
                            pauseAfterMs: pause)
    }

    private func merge(base: VoiceProfile, override: VoiceProfile) -> VoiceProfile {
        // AI override wins on all non-nil / non-zero fields
        return VoiceProfile(
            voiceIdentifier: override.voiceIdentifier ?? base.voiceIdentifier,
            rate: override.rate > 0 ? override.rate : base.rate,
            pitch: override.pitch > 0 ? override.pitch : base.pitch,
            volume: override.volume > 0 ? override.volume : base.volume,
            pauseAfterMs: override.pauseAfterMs > 0 ? override.pauseAfterMs : base.pauseAfterMs
        )
    }
}
