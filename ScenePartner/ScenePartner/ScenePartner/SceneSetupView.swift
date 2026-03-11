// SceneSetupView.swift
import SwiftUI
import AVFoundation

// MARK: - Per-character wrapper so SwiftUI can observe each manager

struct SceneSetupView: View {
    let script: Script
    let partnerCharacters: [Character]
    let elevenLabsAPIKey: String
    let targetVoiceID: String
    let userCharacters: Set<String>

    @EnvironmentObject private var settings: AppSettings
    @State private var selectedCharacterIndex = 0
    @State private var goToRehearsal = false
    @State private var goToSelfTape = false
    @State private var showConfirmReset = false

    // One manager per character, held as StateObjects via a wrapper view
    // We render a hidden CharacterManagerHost for each to keep them alive
    @State private var managerStore: [String: SceneSetupManager] = [:]

    var currentCharacter: Character? {
        guard selectedCharacterIndex < partnerCharacters.count else { return nil }
        return partnerCharacters[selectedCharacterIndex]
    }

    var allSetups: [String: SceneSetup] {
        managerStore.compactMapValues { $0.readyCount > 0 ? $0.setup : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Character tab bar (only when multiple partners)
            if partnerCharacters.count > 1 {
                characterTabBar
                Divider()
            }

            // Render a CharacterSetupPage for the selected character
            if let char = currentCharacter {
                CharacterSetupPage(
                    script: script,
                    character: char,
                    elevenLabsAPIKey: elevenLabsAPIKey,
                    targetVoiceID: targetVoiceID,
                    onManagerReady: { mgr in
                        managerStore[char.name.uppercased()] = mgr
                    }
                )
            } else {
                Spacer()
                Text("Select a character above").foregroundStyle(.secondary)
                Spacer()
            }

            Divider()
            bottomCTAs
        }
        .navigationTitle("Record Partner Lines")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            Group {
                NavigationLink(destination: RehearsalView(
                    script: script,
                    userCharacters: userCharacters,
                    isImprovMode: false,
                    sceneSetups: allSetups
                ), isActive: $goToRehearsal) { EmptyView() }

                NavigationLink(destination: SelfTapeView(
                    script: script,
                    userCharacters: userCharacters,
                    isImprovMode: false,
                    sceneDirection: .empty,
                    sceneSetups: allSetups
                ), isActive: $goToSelfTape) { EmptyView() }
            }
        )
    }

    // MARK: - Character Tab Bar

    private var characterTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(partnerCharacters.enumerated()), id: \.element.id) { i, char in
                    let mgr = managerStore[char.name.uppercased()]
                    let ready = mgr?.readyCount ?? 0
                    let total = mgr?.partnerLines.count ?? 0
                    let isSelected = selectedCharacterIndex == i

                    Button { selectedCharacterIndex = i } label: {
                        VStack(spacing: 3) {
                            Text(char.name)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(ready == total && total > 0 ? Color.green : (ready > 0 ? Color.orange : Color.secondary))
                                    .frame(width: 6, height: 6)
                                Text("\(ready)/\(total)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Rectangle().fill(Color.blue).frame(height: 2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom CTAs (Rehearse first, then Self-Tape as primary)

    private var bottomCTAs: some View {
        VStack(spacing: 10) {
            Button { goToRehearsal = true } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Rehearse First")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button { goToSelfTape = true } label: {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Record Self-Tape")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - CharacterSetupPage
// Each character gets its own page with a real @StateObject manager

struct CharacterSetupPage: View {
    let script: Script
    let character: Character
    let elevenLabsAPIKey: String
    let targetVoiceID: String
    let onManagerReady: (SceneSetupManager) -> Void

    @StateObject private var mgr: SceneSetupManager
    @State private var currentLinePos: Int = 0
    @State private var showConfirmReset = false

    init(script: Script, character: Character, elevenLabsAPIKey: String,
         targetVoiceID: String, onManagerReady: @escaping (SceneSetupManager) -> Void) {
        self.script = script
        self.character = character
        self.elevenLabsAPIKey = elevenLabsAPIKey
        self.targetVoiceID = targetVoiceID
        self.onManagerReady = onManagerReady
        _mgr = StateObject(wrappedValue: SceneSetupManager(
            script: script,
            characterName: character.name,
            elevenLabsAPIKey: elevenLabsAPIKey,
            targetVoiceID: targetVoiceID
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            HStack(spacing: 12) {
                ProgressView(value: Double(mgr.readyCount), total: Double(max(mgr.partnerLines.count, 1)))
                    .tint(mgr.allLinesReady ? .green : .blue)
                Text("\(mgr.readyCount) of \(mgr.partnerLines.count) ready")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer()
                Button(role: .destructive) { showConfirmReset = true } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    if mgr.partnerLines.isEmpty {
                        Text("No lines found for \(character.name)")
                            .foregroundStyle(.secondary).padding(40)
                    } else if currentLinePos < mgr.partnerLines.count {
                        currentLineCard
                        lineList
                    } else {
                        allDoneCard
                        lineList
                    }
                }
                .padding()
            }
        }
        .confirmationDialog("Reset all recordings for \(character.name)?",
            isPresented: $showConfirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                mgr.resetAll()
                currentLinePos = 0
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            onManagerReady(mgr)
            // Request mic permission upfront
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
        .onChange(of: mgr.readyCount) { _, _ in onManagerReady(mgr) }
    }

    // MARK: - Current Line Card

    private var currentLineCard: some View {
        let line = mgr.partnerLines[currentLinePos]

        return VStack(spacing: 14) {
            // Nav row
            HStack {
                Button {
                    if currentLinePos > 0 { currentLinePos -= 1 }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundStyle(currentLinePos > 0 && !mgr.isRecording ? .blue : .secondary)
                }
                .disabled(currentLinePos == 0 || mgr.isRecording)

                Spacer()
                Text("Line \(currentLinePos + 1) of \(mgr.partnerLines.count)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()

                Button {
                    if currentLinePos < mgr.partnerLines.count - 1 { currentLinePos += 1 }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(currentLinePos < mgr.partnerLines.count - 1 && !mgr.isRecording ? .blue : .secondary)
                }
                .disabled(currentLinePos >= mgr.partnerLines.count - 1 || mgr.isRecording)
            }

            // Line text
            Text(line.text)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Record/status control
            recordControl(for: line)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    @ViewBuilder
    private func recordControl(for line: Line) -> some View {
        let lineIndex = line.index
        let status = mgr.lineStatuses[lineIndex] ?? .pending
        let isThisRecording = mgr.isRecording && mgr.currentRecordingIndex == lineIndex

        if isThisRecording {
            VStack(spacing: 10) {
                // Animated mic meter
                HStack(spacing: 3) {
                    ForEach(0..<24, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Float(i) / 24.0 < mgr.audioLevel ? Color.red : Color.red.opacity(0.15))
                            .frame(width: 7, height: CGFloat(6 + i * 2))
                            .animation(.easeOut(duration: 0.05), value: mgr.audioLevel)
                    }
                }
                .frame(height: 56)

                Button {
                    mgr.stopRecordingAndConvert(lineIndex: lineIndex)
                    advanceToNextPending()
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle.fill")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        } else {
            switch status {
            case .converting:
                HStack {
                    ProgressView().tint(.orange)
                    Text("Converting voice...").foregroundStyle(.orange)
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity).padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .ready:
                HStack(spacing: 12) {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    Spacer()
                    Button { mgr.startRecording(lineIndex: lineIndex) } label: {
                        Label("Re-record", systemImage: "mic.fill")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.indigo).clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .failed(let msg):
                VStack(spacing: 8) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                    recordPrimaryButton(lineIndex: lineIndex, label: "Try Again")
                }

            default:
                recordPrimaryButton(lineIndex: lineIndex, label: "Tap to Record")
            }
        }
    }

    private func recordPrimaryButton(lineIndex: Int, label: String) -> some View {
        Button { mgr.startRecording(lineIndex: lineIndex) } label: {
            Label(label, systemImage: "mic.fill")
                .font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding()
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Line List

    private var lineList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All Lines")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(Array(mgr.partnerLines.enumerated()), id: \.element.id) { i, line in
                Button {
                    guard !mgr.isRecording else { return }
                    currentLinePos = i
                } label: {
                    HStack(spacing: 10) {
                        statusIcon(for: line.index).frame(width: 20)
                        Text(line.text)
                            .font(.subheadline).foregroundStyle(.primary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Spacer()
                        if currentLinePos == i {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(currentLinePos == i ? Color.blue.opacity(0.07) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for lineIndex: Int) -> some View {
        switch mgr.lineStatuses[lineIndex] ?? .pending {
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
        case .converting:
            ProgressView().scaleEffect(0.65).tint(.orange)
        case .recording:
            Image(systemName: "mic.fill").foregroundStyle(.red).font(.subheadline)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.subheadline)
        default:
            Image(systemName: "circle").foregroundStyle(.secondary).font(.subheadline)
        }
    }

    // MARK: - All Done Card

    private var allDoneCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("\(character.name)'s lines are ready!").font(.title3.weight(.bold))
            Text("Voice conversion complete. Hit Rehearse or Record Self-Tape below.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func advanceToNextPending() {
        for i in (currentLinePos + 1)..<mgr.partnerLines.count {
            let line = mgr.partnerLines[i]
            if case .ready = mgr.lineStatuses[line.index] ?? .pending { continue }
            currentLinePos = i
            return
        }
        currentLinePos = mgr.partnerLines.count
    }
}
