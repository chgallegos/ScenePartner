// DirectionView.swift
// ScenePartner — Director's notes screen. Set emotional context before rehearsing.

import SwiftUI

struct DirectionView: View {
    let script: Script
    let partnerCharacters: [Character]  // AI characters only
    @Binding var sceneDirection: SceneDirection
    let onStart: () -> Void

    @State private var selectedCharacter: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Scene context
                VStack(alignment: .leading, spacing: 8) {
                    Label("Scene Context", systemImage: "film.stack")
                        .font(.headline)
                    Text("What's the situation? What just happened before this scene?")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $sceneDirection.sceneContext)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Divider()

                // Per-character direction
                VStack(alignment: .leading, spacing: 16) {
                    Label("Character Direction", systemImage: "person.fill.questionmark")
                        .font(.headline)
                    Text("Give the AI partner emotional context for each character.")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(partnerCharacters) { character in
                        CharacterDirectionCard(
                            character: character.name,
                            direction: binding(for: character.name)
                        )
                    }
                }

                Divider()

                // Start button
                Button {
                    onStart()
                } label: {
                    HStack {
                        Spacer()
                        Label("Start Rehearsal", systemImage: "play.fill")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Skip option
                Button("Skip — start without direction") {
                    onStart()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationTitle("Director's Notes")
        .navigationBarTitleDisplayMode(.large)
    }

    private func binding(for name: String) -> Binding<CharacterDirection> {
        Binding(
            get: { sceneDirection.characterDirections[name] ?? .empty(for: name) },
            set: { sceneDirection.characterDirections[name] = $0 }
        )
    }
}

// MARK: - CharacterDirectionCard

struct CharacterDirectionCard: View {
    let character: String
    @Binding var direction: CharacterDirection
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(character)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if isExpanded {
                // Emotional state
                VStack(alignment: .leading, spacing: 4) {
                    Text("Emotional State").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("e.g. desperate, hiding guilt, exhausted", text: $direction.emotionalState)
                        .textFieldStyle(.roundedBorder)
                }

                // Objective
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scene Objective").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("e.g. convince Alex to stay, avoid the truth", text: $direction.objective)
                        .textFieldStyle(.roundedBorder)
                }

                // Tone picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tone").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(TonePreset.allCases) { preset in
                            ToneChip(
                                preset: preset,
                                isSelected: direction.tone.contains(preset.rawValue)
                            ) {
                                if direction.tone.contains(preset.rawValue) {
                                    direction.tone.removeAll { $0 == preset.rawValue }
                                } else {
                                    direction.tone.append(preset.rawValue)
                                }
                            }
                        }
                    }
                }

                // Additional notes
                VStack(alignment: .leading, spacing: 4) {
                    Text("Director's Notes").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("Any other context for the AI...", text: $direction.additionalNotes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ToneChip

struct ToneChip: View {
    let preset: TonePreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(preset.emoji).font(.title3)
                Text(preset.label).font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.tertiarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
    }
}
