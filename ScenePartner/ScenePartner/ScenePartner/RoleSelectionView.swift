// RoleSelectionView.swift
import SwiftUI

struct RoleSelectionView: View {
    let script: Script

    @State private var selectedCharacters: Set<String> = []
    @State private var isImprovMode: Bool = false
    @State private var sceneDirection = SceneDirection.empty
    @State private var showDirection = false
    @State private var navigateToSetup = false
    @State private var sceneSetups: [String: SceneSetup] = [:]

    @EnvironmentObject private var settings: AppSettings

    var partnerCharacters: [Character] {
        script.characters.filter { !selectedCharacters.contains($0.name) }
    }

    /// Check if setups already exist for all partner characters
    var existingSetupCount: Int {
        partnerCharacters.filter { char in
            SceneSetupManager.loadSetup(scriptID: script.id, characterName: char.name) != nil
        }.count
    }

    var body: some View {
        Form {
            Section {
                Text("Select the character(s) you'll be performing. The AI partner plays everyone else.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Section("Your Character") {
                ForEach(script.characters) { character in
                    CharacterRowView(
                        character: character,
                        isSelected: selectedCharacters.contains(character.name)
                    ) { toggle(character.name) }
                }
            }

            Section("Partner Options") {
                Toggle("Improv Mode", isOn: $isImprovMode)
                if isImprovMode {
                    Label("Partner may paraphrase. Disable to enforce script-only.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    showDirection = true
                } label: {
                    HStack {
                        Image(systemName: "theatermasks.fill")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set Character Direction")
                                .font(.body.weight(.medium))
                            Text(hasDirection ? "Direction set ✓" : "Give the AI emotional context")
                                .font(.caption)
                                .foregroundStyle(hasDirection ? .green : .secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                    }
                }
                .disabled(selectedCharacters.isEmpty)
            }

            // MARK: - Hybrid Setup Section
            Section {
                NavigationLink(
                    destination: setupDestination,
                    isActive: $navigateToSetup
                ) { EmptyView() }.hidden()

                Button {
                    loadExistingSetups()
                    navigateToSetup = true
                } label: {
                    HStack {
                        Image(systemName: "waveform.and.mic")
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Record Partner Lines")
                                .font(.body.weight(.medium))
                            Group {
                                if existingSetupCount > 0 {
                                    Text("\(existingSetupCount) of \(partnerCharacters.count) character(s) recorded ✓")
                                        .foregroundStyle(.green)
                                } else {
                                    Text("Your emotion, their voice — best results")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                    }
                }
                .disabled(selectedCharacters.isEmpty)
            } header: {
                Text("Hybrid Rehearsal")
            } footer: {
                Text("Record the partner's lines yourself with the right emotion. The app converts your voice to sound like a different person.")
                    .font(.caption)
            }

            Section {
                // Rehearse button
                NavigationLink(
                    destination: RehearsalView(
                        script: script,
                        userCharacters: selectedCharacters,
                        isImprovMode: isImprovMode,
                        sceneDirection: sceneDirection,
                        sceneSetups: loadedSetups()
                    )
                ) {
                    HStack {
                        Image(systemName: "play.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rehearse").font(.headline)
                            Text(loadedSetups().isEmpty ? "AI voice mode" : "Hybrid mode active")
                                .font(.caption)
                                .foregroundStyle(loadedSetups().isEmpty ? .secondary : .indigo)
                        }
                        Spacer()
                    }
                }
                .disabled(selectedCharacters.isEmpty)

                // Self-Tape button
                NavigationLink(
                    destination: SelfTapeView(
                        script: script,
                        userCharacters: selectedCharacters,
                        isImprovMode: isImprovMode,
                        sceneDirection: sceneDirection
                    )
                ) {
                    HStack {
                        Image(systemName: "video.fill").foregroundStyle(.red)
                        Text("Record Self-Tape").font(.headline)
                        Spacer()
                        Text("Camera + AI partner").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(selectedCharacters.isEmpty)
            }
        }
        .navigationTitle(script.title)
        .sheet(isPresented: $showDirection) {
            NavigationStack {
                DirectionView(
                    script: script,
                    partnerCharacters: partnerCharacters,
                    sceneDirection: $sceneDirection
                ) {
                    showDirection = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showDirection = false }
                    }
                }
            }
        }
        .onAppear { loadExistingSetups() }
    }

    // MARK: - Setup Destination

    @ViewBuilder
    private var setupDestination: some View {
        if let firstPartner = partnerCharacters.first {
            SceneSetupView(
                script: script,
                characterName: firstPartner.name,
                elevenLabsAPIKey: settings.elevenLabsAPIKey,
                targetVoiceID: settings.elevenLabsVoiceID,
                onComplete: { setup in
                    sceneSetups[firstPartner.name.uppercased()] = setup
                    navigateToSetup = false
                },
                onSkip: {
                    navigateToSetup = false
                }
            )
        }
    }

    // MARK: - Helpers

    private func loadExistingSetups() {
        for char in partnerCharacters {
            if let setup = SceneSetupManager.loadSetup(scriptID: script.id, characterName: char.name) {
                sceneSetups[char.name.uppercased()] = setup
            }
        }
    }

    private func loadedSetups() -> [String: SceneSetup] {
        // Merge in-memory setups with any saved ones
        var result = sceneSetups
        for char in partnerCharacters {
            if result[char.name.uppercased()] == nil,
               let saved = SceneSetupManager.loadSetup(scriptID: script.id, characterName: char.name) {
                result[char.name.uppercased()] = saved
            }
        }
        return result
    }

    private var hasDirection: Bool {
        !sceneDirection.sceneContext.isEmpty ||
        sceneDirection.characterDirections.values.contains { !$0.emotionalState.isEmpty }
    }

    private func toggle(_ name: String) {
        if selectedCharacters.contains(name) { selectedCharacters.remove(name) }
        else { selectedCharacters.insert(name) }
    }
}

struct CharacterRowView: View {
    let character: Character
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name).font(.headline).foregroundStyle(.primary)
                    Text("\(character.lineCount) lines").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue).font(.title2)
                }
            }
        }
    }
}
