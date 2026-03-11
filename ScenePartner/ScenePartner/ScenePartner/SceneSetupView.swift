// SceneSetupView.swift
// The "setup phase" UI — user records each partner line one at a time.
// ElevenLabs Voice Changer converts the voice in the background.

import SwiftUI
import AVFoundation

struct SceneSetupView: View {
    let script: Script
    let characterName: String
    let onComplete: (SceneSetup) -> Void
    let onSkip: () -> Void

    @StateObject private var manager: SceneSetupManager
    @EnvironmentObject private var settings: AppSettings
    @State private var currentLinePos: Int = 0
    @State private var showConfirmReset = false
    @State private var hasRequestedMicPermission = false

    init(script: Script, characterName: String, elevenLabsAPIKey: String, targetVoiceID: String,
         onComplete: @escaping (SceneSetup) -> Void, onSkip: @escaping () -> Void) {
        self.script = script
        self.characterName = characterName
        self.onComplete = onComplete
        self.onSkip = onSkip
        _manager = StateObject(wrappedValue: SceneSetupManager(
            script: script,
            characterName: characterName,
            elevenLabsAPIKey: elevenLabsAPIKey,
            targetVoiceID: targetVoiceID
        ))
    }

    var currentLine: Line? {
        guard currentLinePos < manager.partnerLines.count else { return nil }
        return manager.partnerLines[currentLinePos]
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    instructionCard
                    if let line = currentLine {
                        currentLineCard(line: line)
                    } else {
                        allDoneCard
                    }
                    lineListSection
                }
                .padding()
            }
            Divider()
            bottomBar
        }
        .navigationTitle("Record \(characterName)'s Lines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Reset All Recordings", systemImage: "trash", role: .destructive) {
                        showConfirmReset = true
                    }
                    Button("Skip Setup", systemImage: "forward.fill") { onSkip() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Reset all recordings for \(characterName)?", isPresented: $showConfirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { requestMicPermission() }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(manager.readyCount) of \(manager.partnerLines.count) lines ready")
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: Double(manager.readyCount), total: Double(max(manager.partnerLines.count, 1)))
                    .tint(.green)
                    .frame(width: 200)
            }
            Spacer()
            if manager.allLinesReady {
                Label("All Ready!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Instruction Card

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How this works", systemImage: "theatermasks.fill")
                .font(.headline)
                .foregroundStyle(.purple)
            Text("Read each of \(characterName)'s lines out loud — with the emotion and timing you want. Your voice will be converted to sound like a different person. This becomes your rehearsal partner.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Current Line Card

    private func currentLineCard(line: Line) -> some View {
        VStack(spacing: 16) {
            // Line number badge
            HStack {
                Text("Line \(currentLinePos + 1) of \(manager.partnerLines.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge(for: line.index)
            }

            // The actual line text
            Text(line.text)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Record button
            recordButton(for: line)

            // Navigation between lines
            HStack(spacing: 24) {
                Button {
                    if currentLinePos > 0 { currentLinePos -= 1 }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                        .foregroundStyle(currentLinePos > 0 ? .blue : .secondary)
                }
                .disabled(currentLinePos == 0 || manager.isRecording)

                Spacer()

                Button {
                    if currentLinePos < manager.partnerLines.count - 1 { currentLinePos += 1 }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title)
                        .foregroundStyle(currentLinePos < manager.partnerLines.count - 1 ? .blue : .secondary)
                }
                .disabled(currentLinePos >= manager.partnerLines.count - 1 || manager.isRecording)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func recordButton(for line: Line) -> some View {
        let status = manager.lineStatuses[line.index] ?? .pending
        let isThisLineRecording = manager.isRecording && manager.currentRecordingIndex == line.index

        VStack(spacing: 12) {
            if isThisLineRecording {
                // Live recording state
                VStack(spacing: 8) {
                    // Audio level meter
                    HStack(spacing: 3) {
                        ForEach(0..<20, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Float(i) / 20.0 < manager.audioLevel ? Color.red : Color.red.opacity(0.15))
                                .frame(width: 8, height: CGFloat(8 + i * 2))
                        }
                    }
                    .frame(height: 50)

                    Button {
                        manager.stopRecordingAndConvert(lineIndex: line.index)
                        // Auto-advance to next unrecorded line
                        advanceToNextPending()
                    } label: {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("Stop Recording")
                        }
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
                    VStack(spacing: 8) {
                        Label("Ready!", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        Button {
                            manager.startRecording(lineIndex: line.index)
                        } label: {
                            Text("Re-record")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                case .failed(let msg):
                    VStack(spacing: 6) {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        recordButtonPrimary(lineIndex: line.index, label: "Try Again")
                    }

                default:
                    recordButtonPrimary(lineIndex: line.index, label: "Hold to Record")
                }
            }
        }
    }

    private func recordButtonPrimary(lineIndex: Int, label: String) -> some View {
        Button {
            manager.startRecording(lineIndex: lineIndex)
        } label: {
            HStack {
                Image(systemName: "mic.fill")
                Text(label)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - All Done Card

    private var allDoneCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("All lines recorded!")
                .font(.title2.weight(.bold))
            Text("Your emotional performances have been converted. You're ready to rehearse.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Line List

    private var lineListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Lines")
                .font(.headline)
                .padding(.bottom, 2)

            ForEach(Array(manager.partnerLines.enumerated()), id: \.element.id) { i, line in
                Button {
                    guard !manager.isRecording else { return }
                    currentLinePos = i
                } label: {
                    HStack(spacing: 12) {
                        statusIcon(for: line.index)
                            .frame(width: 24)
                        Text(line.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if currentLinePos == i {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(currentLinePos == i ? Color.blue.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button("Skip for Now") { onSkip() }
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onComplete(manager.setup)
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text(manager.allLinesReady ? "Start Rehearsal" : "Rehearse with \(manager.readyCount) Lines")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(manager.readyCount > 0 ? Color.blue : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(manager.readyCount == 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func statusBadge(for lineIndex: Int) -> some View {
        let status = manager.lineStatuses[lineIndex] ?? .pending
        switch status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                .font(.caption.weight(.semibold))
        case .converting:
            Label("Converting", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                .font(.caption.weight(.semibold))
        case .recording:
            Label("Recording", systemImage: "mic.fill").foregroundStyle(.red)
                .font(.caption.weight(.semibold))
        default:
            Label("Pending", systemImage: "circle").foregroundStyle(.secondary)
                .font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder
    private func statusIcon(for lineIndex: Int) -> some View {
        let status = manager.lineStatuses[lineIndex] ?? .pending
        switch status {
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .converting:
            ProgressView().scaleEffect(0.7).tint(.orange)
        case .recording:
            Image(systemName: "mic.fill").foregroundStyle(.red)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        default:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func advanceToNextPending() {
        // Find the next line that isn't ready yet
        for i in (currentLinePos + 1)..<manager.partnerLines.count {
            let line = manager.partnerLines[i]
            if case .ready = manager.lineStatuses[line.index] ?? .pending { continue }
            currentLinePos = i
            return
        }
        // All done — jump past the list to show the "all done" card
        currentLinePos = manager.partnerLines.count
    }

    private func resetAll() {
        SceneSetupManager.deleteSetup(scriptID: script.id, characterName: characterName)
        // Reinit manager
        currentLinePos = 0
    }

    private func requestMicPermission() {
        guard !hasRequestedMicPermission else { return }
        hasRequestedMicPermission = true
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }
}
