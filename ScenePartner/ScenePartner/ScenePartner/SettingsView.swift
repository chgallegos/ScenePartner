// SettingsView.swift
import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var showAPIKey = false

    var body: some View {
        Form {
            // MARK: - AI Voice
            Section {
                Toggle("Use AI Voice (ElevenLabs)", isOn: $settings.useAIVoice)

                if settings.useAIVoice {
                    HStack {
                        if showAPIKey {
                            TextField("API Key", text: $settings.elevenLabsAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("API Key", text: $settings.elevenLabsAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if settings.elevenLabsAPIKey.isEmpty {
                        Label("Get a free API key at elevenlabs.io", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("AI voice active — partner will sound human", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }

                    // Voice picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Partner Voice").font(.caption).foregroundStyle(.secondary)
                        Picker("Voice", selection: $settings.elevenLabsVoiceID) {
                            // Male voices
                            Text("Daniel — deep, clear").tag("onwK4e9ZLuTAKqWW03F9")
                            Text("Adam — dramatic, powerful").tag("pNInz6obpgDQGcFmaJgB")
                            Text("Josh — warm, grounded").tag("TxGEqnHWrfWFTfGW9XjX")
                            Text("Antoni — natural, conversational").tag("ErXwobaYiN019PkySvjV")
                            // Female voices
                            Text("Bella — warm, natural").tag("EXAVITQu4vr4xnSDxMaL")
                            Text("Elli — emotional, expressive").tag("MF3mGyEYCl7XYWbV9V6O")
                        }
                        .pickerStyle(.navigationLink)
                        Text("Try Adam or Elli for most emotional range.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("AI Voice")
            } footer: {
                Text("When enabled, the partner's lines are spoken by a neural AI voice. Falls back to device TTS when offline.")
                    .font(.caption)
            }

            // MARK: - Privacy
            // MARK: - Adaptive Director
            Section {
                Toggle("Adaptive Direction", isOn: $settings.adaptiveDirectionEnabled)
                if settings.adaptiveDirectionEnabled {
                    HStack {
                        SecureField("OpenAI API Key", text: $settings.openAIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !settings.openAIKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    if settings.openAIKey.isEmpty {
                        Label("Get a key at platform.openai.com", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("AI will evolve character direction as scene develops", systemImage: "brain")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Adaptive Direction")
            } footer: {
                Text("Uses GPT-4o-mini to analyze the scene every 2 exchanges and update the partner's emotional delivery in real time.")
                    .font(.caption)
            }

            Section("Privacy") {
                Toggle("Local Only Mode", isOn: $settings.localOnlyMode)
                if settings.localOnlyMode {
                    Label("All network calls disabled.", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            // MARK: - Teleprompter
            Section("Teleprompter") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Font Size"); Spacer()
                        Text("\(Int(settings.defaultFontSize))pt").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.defaultFontSize, in: 14...72, step: 1)
                }
                Toggle("Mirror Mode", isOn: $settings.mirrorMode)
            }

            // MARK: - Fallback Voice
            Section("Fallback Voice (Offline)") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Speech Rate"); Spacer()
                        Text(String(format: "%.2f", settings.defaultSpeechRate)).foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.defaultSpeechRate, in: 0.1...0.9, step: 0.05)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Pitch"); Spacer()
                        Text(String(format: "%.1f", settings.defaultSpeechPitch)).foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.defaultSpeechPitch, in: 0.5...2.0, step: 0.1)
                }
            }

            // MARK: - About
            Section("About") {
                HStack {
                    Text("Version"); Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            availableVoices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("en") }.sorted { $0.name < $1.name }
        }
    }
}
