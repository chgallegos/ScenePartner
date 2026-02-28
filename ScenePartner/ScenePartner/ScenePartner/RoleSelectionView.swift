// RoleSelectionView.swift
import SwiftUI

struct RoleSelectionView: View {
    let script: Script

    @State private var selectedCharacters: Set<String> = []
    @State private var isImprovMode: Bool = false
    @State private var sceneDirection = SceneDirection.empty
    @State private var showDirection = false

    var partnerCharacters: [Character] {
        script.characters.filter { !selectedCharacters.contains($0.name) }
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
                // Direction button
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

            Section {
                // Rehearse button
                NavigationLink(
                    destination: RehearsalView(
                        script: script,
                        userCharacters: selectedCharacters,
                        isImprovMode: isImprovMode,
                        sceneDirection: sceneDirection
                    )
                ) {
                    HStack {
                        Image(systemName: "play.fill").foregroundStyle(.blue)
                        Text("Rehearse").font(.headline)
                        Spacer()
                        Text("Practice mode").font(.caption).foregroundStyle(.secondary)
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
