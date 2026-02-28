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
}

    // MARK: - AI Voice
    @AppStorage("elevenLabsAPIKey") var elevenLabsAPIKey: String = ""
    @AppStorage("elevenLabsVoiceID") var elevenLabsVoiceID: String = ElevenLabsVoiceEngine.defaultVoiceID
    @AppStorage("useAIVoice") var useAIVoice: Bool = false
