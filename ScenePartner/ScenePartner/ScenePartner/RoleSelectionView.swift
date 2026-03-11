// RoleSelectionView.swift
import SwiftUI

struct RoleSelectionView: View {
    let script: Script

    @State private var selectedCharacters: Set<String> = []
    @State private var goToSetup = false

    @EnvironmentObject private var settings: AppSettings

    var partnerCharacters: [Character] {
        script.characters.filter { !selectedCharacters.contains($0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text("Which character are you playing?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section("Characters") {
                    ForEach(script.characters) { character in
                        CharacterRowView(
                            character: character,
                            isSelected: selectedCharacters.contains(character.name)
                        ) { toggle(character.name) }
                    }
                }
            }
            .listStyle(.insetGrouped)

            Divider()

            NavigationLink(
                destination: SceneSetupView(
                    script: script,
                    partnerCharacters: partnerCharacters,
                    elevenLabsAPIKey: settings.elevenLabsAPIKey,
                    targetVoiceID: settings.elevenLabsVoiceID,
                    userCharacters: selectedCharacters
                ),
                isActive: $goToSetup
            ) { EmptyView() }

            Button {
                goToSetup = true
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Continue")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedCharacters.isEmpty ? Color.secondary : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .disabled(selectedCharacters.isEmpty)
        }
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.large)
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title2)
            }
            .contentShape(Rectangle())
        }
    }
}
