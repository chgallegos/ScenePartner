// SpeechRecognizer.swift
// ScenePartner — Offline speech recognition using SFSpeechRecognizer.
// Listens for the user speaking their line and calls completion when done.

import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {

    @Published private(set) var isListening = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var permissionGranted = false

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var onComplete: ((String) -> Void)?

    // How long to wait after speech stops before auto-advancing (seconds)
    private let silenceThreshold: TimeInterval = 1.5

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestPermission()
    }

    // MARK: - Permissions

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.permissionGranted = status == .authorized
            }
        }
    }

    // MARK: - Listen

    /// Start listening. Calls completion with transcribed text after silence.
    func startListening(completion: @escaping (String) -> Void) {
        guard permissionGranted else {
            requestPermission()
            return
        }
        guard !isListening else { return }

        onComplete = completion
        transcribedText = ""

        do {
            try startAudioEngine()
            isListening = true
        } catch {
            print("[SpeechRecognizer] Failed to start: \(error)")
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Audio Engine

    private func startAudioEngine() throws {
        // Configure audio session for recording while allowing playback
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        // Use on-device recognition — works offline
        recognitionRequest.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcribedText = text
                    // Reset silence timer on each new word
                    self.resetSilenceTimer()
                }
            }

            if error != nil || (result?.isFinal == true) {
                Task { @MainActor in
                    self.finishListening()
                }
            }
        }

        // Start silence timer — if user doesn't speak within 8s, give up
        resetSilenceTimer(initial: true)
    }

    private func resetSilenceTimer(initial: Bool = false) {
        silenceTimer?.invalidate()
        let timeout = initial ? 8.0 : silenceThreshold
        silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finishListening()
            }
        }
    }

    private func finishListening() {
        let text = transcribedText
        stopListening()
        onComplete?(text)
        onComplete = nil
    }
}
