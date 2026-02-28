// AppSettings.swift
import SwiftUI

@Observable
final class AppSettings {
    var localOnlyMode: Bool {
        get { UserDefaults.standard.bool(forKey: "localOnlyMode") }
        set { UserDefaults.standard.set(newValue, forKey: "localOnlyMode") }
    }
    var toneAnalysisEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "toneAnalysisEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "toneAnalysisEnabled") }
    }
    var coachingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "coachingEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "coachingEnabled") }
    }
    var defaultFontSize: Double {
        get { UserDefaults.standard.double(forKey: "defaultFontSize") == 0 ? 28 : UserDefaults.standard.double(forKey: "defaultFontSize") }
        set { UserDefaults.standard.set(newValue, forKey: "defaultFontSize") }
    }
    var mirrorMode: Bool {
        get { UserDefaults.standard.bool(forKey: "mirrorMode") }
        set { UserDefaults.standard.set(newValue, forKey: "mirrorMode") }
    }
    var defaultSpeechRate: Double {
        get { UserDefaults.standard.double(forKey: "defaultSpeechRate") == 0 ? 0.5 : UserDefaults.standard.double(forKey: "defaultSpeechRate") }
        set { UserDefaults.standard.set(newValue, forKey: "defaultSpeechRate") }
    }
    var defaultSpeechPitch: Double {
        get { UserDefaults.standard.double(forKey: "defaultSpeechPitch") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "defaultSpeechPitch") }
        set { UserDefaults.standard.set(newValue, forKey: "defaultSpeechPitch") }
    }
    var defaultVoiceIdentifier: String {
        get { UserDefaults.standard.string(forKey: "defaultVoiceIdentifier") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "defaultVoiceIdentifier") }
    }
}
