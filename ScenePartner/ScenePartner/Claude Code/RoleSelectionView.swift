// RoleSelectionView.swift
// ScenePartner — User picks which character(s) they are playing.

import SwiftUI

struct RoleSelectionView: View {

    let script: Script

    @State private var selectedCharacters: Set<String> = []
    @State private var isImprovMode: Bool = false
    @State private var navigateToRehearsal = false

    var body: some View {
        Form {
            Section {
                Text("Select the character(s) you'll be performing. The AI partner will play everyone else.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Characters") {
                ForEach(script.characters) { character in
                    CharacterRowView(
                        character: character,
                        isSelected: selectedCharacters.contains(character.name)
                    ) {
                        toggle(character.name)
                    }
                }
            }

            Section("Partner Options") {
                Toggle("Improv Mode", isOn: $isImprovMode)
                if isImprovMode {
                    Label("Partner may paraphrase. Disable to enforce script-only.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                NavigationLink(
                    destination: RehearsalView(
                        script: script,
                        userCharacters: selectedCharacters,
                        isImprovMode: isImprovMode
                    )
                ) {
                    HStack {
                        Spacer()
                        Label("Start Rehearsal", systemImage: "play.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(selectedCharacters.isEmpty)
            }
        }
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.large)
    }

    private func toggle(_ name: String) {
        if selectedCharacters.contains(name) {
            selectedCharacters.remove(name)
        } else {
            selectedCharacters.insert(name)
        }
    }
}

// MARK: - CharacterRowView

struct CharacterRowView: View {
    let character: Character
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(character.lineCount) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                }
            }
        }
    }
}
