// SceneSetupView.swift
// Setup phase: record all partner lines for all partner characters.
// Multi-character tab support. Re-record always available.
// Primary CTAs: Rehearse + Record Self-Tape.

import SwiftUI
import AVFoundation

struct SceneSetupView: View {
    let script: Script
    let partnerCharacters: [Character]
    let elevenLabsAPIKey: String
    let targetVoiceID: String
    let userCharacters: Set<String>

    @EnvironmentObject private var settings: AppSettings
    @State private var selectedCharacterIndex = 0
    @State private var managers: [String: SceneSetupManager] = [:]
    @State private var currentLinePos: Int = 0
    @State private var showConfirmReset = false
    @State private var goToRehearsal = false
    @State private var goToSelfTape = false

    var currentCharacter: Character? {
        guard selectedCharacterIndex < partnerCharacters.count else { return nil }
        return partnerCharacters[selectedCharacterIndex]
    }

    var currentManager: SceneSetupManager? {
        guard let char = currentCharacter else { return nil }
        return managers[char.name.uppercased()]
    }

    var allSetups: [String: SceneSetup] {
        managers.compactMapValues { $0.readyCount > 0 ? $0.setup : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Multi-character tab bar
            if partnerCharacters.count > 1 {
                characterTabBar
                Divider()
            }

            // Progress header
            if let mgr = currentManager {
                progressHeader(mgr)
                Divider()
            }

            // Line content
            ScrollView {
                VStack(spacing: 16) {
                    if partnerCharacters.isEmpty {
                        noPartnerView
                    } else if let char = currentCharacter, let mgr = currentManager {
                        if mgr.partnerLines.isEmpty {
                            noLinesView(char)
                        } else if currentLinePos < mgr.partnerLines.count {
                            currentLineCard(mgr: mgr, char: char)
                            lineListSection(mgr: mgr)
                        } else {
                            allDoneCard(char: char, mgr: mgr)
                            lineListSection(mgr: mgr)
                        }
                    }
                }
                .padding()
            }

            Divider()
            bottomCTAs
        }
        .navigationTitle("Record Partner Lines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if currentManager != nil {
                    Button(role: .destructive) { showConfirmReset = true } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
        }
        .confirmationDialog(
            "Reset recordings for \(currentCharacter?.name ?? "")?",
            isPresented: $showConfirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                if let char = currentCharacter {
                    SceneSetupManager.deleteSetup(scriptID: script.id, characterName: char.name)
                    initManager(for: char)
                    currentLinePos = 0
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { initAllManagers() }
        .onChange(of: selectedCharacterIndex) { _, _ in currentLinePos = 0 }
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
                    let mgr = managers[char.name.uppercased()]
                    let ready = mgr?.readyCount ?? 0
                    let total = mgr?.partnerLines.count ?? 0

                    Button {
                        selectedCharacterIndex = i
                    } label: {
                        VStack(spacing: 3) {
                            Text(char.name)
                                .font(.subheadline.weight(selectedCharacterIndex == i ? .semibold : .regular))
                                .foregroundStyle(selectedCharacterIndex == i ? .primary : .secondary)
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(ready == total && total > 0 ? Color.green : (ready > 0 ? Color.orange : Color.secondary))
                                    .frame(width: 6, height: 6)
                                Text("\(ready)/\(total)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if selectedCharacterIndex == i {
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(height: 2)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Progress Header

    private func progressHeader(_ mgr: SceneSetupManager) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(mgr.readyCount), total: Double(max(mgr.partnerLines.count, 1)))
                .tint(mgr.allLinesReady ? .green : .blue)
            Text("\(mgr.readyCount) of \(mgr.partnerLines.count) ready")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Current Line Card

    private func currentLineCard(mgr: SceneSetupManager, char: Character) -> some View {
        let line = mgr.partnerLines[currentLinePos]

        return VStack(spacing: 14) {
            // Navigation arrows + counter
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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

            // Record control
            recordControl(mgr: mgr, lineIndex: line.index)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    @ViewBuilder
    private func recordControl(mgr: SceneSetupManager, lineIndex: Int) -> some View {
        let status = mgr.lineStatuses[lineIndex] ?? .pending
        let isThisRecording = mgr.isRecording && mgr.currentRecordingIndex == lineIndex

        if isThisRecording {
            VStack(spacing: 10) {
                // Live mic meter
                HStack(spacing: 3) {
                    ForEach(0..<24, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Float(i) / 24.0 < mgr.audioLevel ? Color.red : Color.red.opacity(0.15))
                            .frame(width: 7, height: CGFloat(6 + i * 2))
                    }
                }
                .frame(height: 56)
                .animation(.easeOut(duration: 0.05), value: mgr.audioLevel)

                Button {
                    mgr.stopRecordingAndConvert(lineIndex: lineIndex)
                    advanceToNextPending(mgr: mgr)
                } label: {
                    Label("Done — Stop Recording", systemImage: "stop.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
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
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .ready:
                HStack(spacing: 12) {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Button {
                        mgr.startRecording(lineIndex: lineIndex)
                    } label: {
                        Label("Re-record", systemImage: "mic.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.indigo)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .failed(let msg):
                VStack(spacing: 8) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                    recordPrimaryButton(mgr: mgr, lineIndex: lineIndex, label: "Try Again")
                }

            default:
                recordPrimaryButton(mgr: mgr, lineIndex: lineIndex, label: "Tap to Record")
            }
        }
    }

    private func recordPrimaryButton(mgr: SceneSetupManager, lineIndex: Int, label: String) -> some View {
        Button { mgr.startRecording(lineIndex: lineIndex) } label: {
            Label(label, systemImage: "mic.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Line List

    private func lineListSection(mgr: SceneSetupManager) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All Lines")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(Array(mgr.partnerLines.enumerated()), id: \.element.id) { i, line in
                Button {
                    guard !mgr.isRecording else { return }
                    currentLinePos = i
                } label: {
                    HStack(spacing: 10) {
                        lineStatusIcon(mgr: mgr, lineIndex: line.index)
                            .frame(width: 20)
                        Text(line.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if currentLinePos == i {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(currentLinePos == i ? Color.blue.opacity(0.07) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private func lineStatusIcon(mgr: SceneSetupManager, lineIndex: Int) -> some View {
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

    private func allDoneCard(char: Character, mgr: SceneSetupManager) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("\(char.name)'s lines are ready!")
                .font(.title3.weight(.bold))
            Text("Your emotional performance has been voice-converted. Ready to roll.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var noPartnerView: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No partner characters found").font(.headline)
            Text("This script may only have one character.").foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private func noLinesView(_ char: Character) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No lines for \(char.name)").font(.headline)
        }
        .padding(32)
    }

    // MARK: - Bottom CTAs

    private var bottomCTAs: some View {
        VStack(spacing: 10) {
            // Primary: Self-Tape
            Button { goToSelfTape = true } label: {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Record Self-Tape")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Secondary: Rehearse
            Button { goToRehearsal = true } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Rehearse First")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func initAllManagers() {
        for char in partnerCharacters {
            initManager(for: char)
        }
    }

    private func initManager(for char: Character) {
        let mgr = SceneSetupManager(
            script: script,
            characterName: char.name,
            elevenLabsAPIKey: elevenLabsAPIKey,
            targetVoiceID: targetVoiceID
        )
        managers[char.name.uppercased()] = mgr
    }

    private func advanceToNextPending(mgr: SceneSetupManager) {
        for i in (currentLinePos + 1)..<mgr.partnerLines.count {
            let line = mgr.partnerLines[i]
            if case .ready = mgr.lineStatuses[line.index] ?? .pending { continue }
            currentLinePos = i
            return
        }
        currentLinePos = mgr.partnerLines.count
    }
}
