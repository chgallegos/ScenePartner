// SettingsView.swift
// ScenePartner — User-facing settings screen.

import SwiftUI
import AVFoundation

struct SettingsView: View {

    @EnvironmentObject private var settings: AppSettings
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        Form {
            // MARK: Privacy & Network
            Section {
                Toggle("Local Only Mode", isOn: $settings.localOnlyMode)
                if settings.localOnlyMode {
                    Label("All AI features disabled. No data leaves your device.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("When online, optional AI enhancements are available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Privacy")
            }

            // MARK: Online Features (shown only when not local-only)
            if !settings.localOnlyMode {
                Section("Online Features") {
                    Toggle("Tone Analysis", isOn: $settings.toneAnalysisEnabled)
                    Toggle("Coaching Feedback", isOn: $settings.coachingEnabled)
                }
            }

            // MARK: Teleprompter
            Section("Teleprompter") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(settings.defaultFontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.defaultFontSize, in: 14...72, step: 1)
                }
                Toggle("Mirror Mode", isOn: $settings.mirrorMode)
            }

            // MARK: Voice
            Section("Default Voice") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Speech Rate")
                        Spacer()
                        Text(String(format: "%.2f", settings.defaultSpeechRate))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.defaultSpeechRate, in: 0.1...0.9, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Pitch")
                        Spacer()
                        Text(String(format: "%.1f", settings.defaultSpeechPitch))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.defaultSpeechPitch, in: 0.5...2.0, step: 0.1)
                }

                if !availableVoices.isEmpty {
                    Picker("Voice", selection: $settings.defaultVoiceIdentifier) {
                        Text("System Default").tag("")
                        ForEach(availableVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))")
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            // MARK: About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                Link("Privacy Policy", destination: URL(string: "https://yourapp.example/privacy")!)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            availableVoices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("en") }
                .sorted { $0.name < $1.name }
        }
    }
}
