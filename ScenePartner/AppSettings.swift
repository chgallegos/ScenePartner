// AppSettings.swift
// ScenePartner — Persisted user preferences via @AppStorage.

import SwiftUI
import Combine

final class AppSettings: ObservableObject {

    // MARK: - Online / Privacy

    /// When true, ALL network calls are disabled regardless of connectivity.
    @AppStorage("localOnlyMode") var localOnlyMode: Bool = false

    /// Whether the optional tone analysis feature is enabled.
    @AppStorage("toneAnalysisEnabled") var toneAnalysisEnabled: Bool = true

    /// Whether the post-run coaching feedback feature is enabled.
    @AppStorage("coachingEnabled") var coachingEnabled: Bool = true

    // MARK: - Teleprompter Defaults

    @AppStorage("defaultFontSize") var defaultFontSize: Double = 28
    @AppStorage("defaultScrollSpeed") var defaultScrollSpeed: Double = 1.0
    @AppStorage("mirrorMode") var mirrorMode: Bool = false

    // MARK: - Voice Defaults

    /// BCP-47 voice identifier (nil = system default)
    @AppStorage("defaultVoiceIdentifier") var defaultVoiceIdentifier: String = ""

    @AppStorage("defaultSpeechRate") var defaultSpeechRate: Double = 0.5
    @AppStorage("defaultSpeechPitch") var defaultSpeechPitch: Double = 1.0
}
