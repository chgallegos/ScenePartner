// SettingsView.swift
import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showAPIKey = false

    var body: some View {
        Form {
            // MARK: - ElevenLabs
            Section {
                HStack {
                    if showAPIKey {
                        TextField("ElevenLabs API Key", text: $settings.elevenLabsAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("ElevenLabs API Key", text: $settings.elevenLabsAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button { showAPIKey.toggle() } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.elevenLabsAPIKey.isEmpty {
                    Label("Get a free key at elevenlabs.io", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Connected — voice conversion active", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }

                // Partner voice picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Partner Voice").font(.caption).foregroundStyle(.secondary)
                    Picker("Voice", selection: $settings.elevenLabsVoiceID) {
                        Text("Daniel — deep, clear").tag("onwK4e9ZLuTAKqWW03F9")
                        Text("Adam — dramatic, powerful").tag("pNInz6obpgDQGcFmaJgB")
                        Text("Josh — warm, grounded").tag("TxGEqnHWrfWFTfGW9XjX")
                        Text("Antoni — natural").tag("ErXwobaYiN019PkySvjV")
                        Text("Bella — warm, natural").tag("EXAVITQu4vr4xnSDxMaL")
                        Text("Elli — emotional, expressive").tag("MF3mGyEYCl7XYWbV9V6O")
                    }
                    .pickerStyle(.navigationLink)
                    Text("This voice is used for both partner lines and voice conversion.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } header: {
                Text("ElevenLabs Voice")
            } footer: {
                Text("Required for hybrid mode voice conversion and AI partner voice.")
                    .font(.caption)
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
    }
}

