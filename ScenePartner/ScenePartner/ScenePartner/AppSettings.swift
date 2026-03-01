// AppSettings.swift
import SwiftUI

final class AppSettings: ObservableObject {
    @AppStorage("localOnlyMode") var localOnlyMode: Bool = false
    @AppStorage("toneAnalysisEnabled") var toneAnalysisEnabled: Bool = true
    @AppStorage("coachingEnabled") var coachingEnabled: Bool = true
    @AppStorage("defaultFontSize") var defaultFontSize: Double = 28
    @AppStorage("mirrorMode") var mirrorMode: Bool = false
    @AppStorage("defaultSpeechRate") var defaultSpeechRate: Double = 0.5
    @AppStorage("defaultSpeechPitch") var defaultSpeechPitch: Double = 1.0
    @AppStorage("defaultVoiceIdentifier") var defaultVoiceIdentifier: String = ""
    @AppStorage("elevenLabsAPIKey") var elevenLabsAPIKey: String = ""
    @AppStorage("elevenLabsVoiceID") var elevenLabsVoiceID: String = "onwK4e9ZLuTAKqWW03F9"
    @AppStorage("useAIVoice") var useAIVoice: Bool = false

    // MARK: - Adaptive Director
    @AppStorage("openAIKey") var openAIKey: String = ""
    @AppStorage("adaptiveDirectionEnabled") var adaptiveDirectionEnabled: Bool = true
}
