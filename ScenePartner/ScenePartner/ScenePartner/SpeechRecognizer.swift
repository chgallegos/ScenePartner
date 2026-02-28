// SpeechRecognizer.swift
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

    private let silenceThreshold: TimeInterval = 0.7
    private let maxListenTime: TimeInterval = 30.0

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestPermission()
    }

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.permissionGranted = status == .authorized
            }
        }
    }

    func startListening(completion: @escaping (String) -> Void) {
        guard permissionGranted else {
            requestPermission()
            // Don't call completion — let user grant permission first
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
            isListening = false
            // Fail gracefully — don't auto-advance, let user tap manually
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        // Restore audio session for TTS playback
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func startAudioEngine() throws {
        // Clean up any previous session
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        // Switch audio session to record mode
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        // Don't require on-device — allows fallback to server recognition
        // which is more reliable across simulator + device
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0 && nativeFormat.channelCount > 0 else {
            throw SpeechError.invalidFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
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
                    self.resetSilenceTimer()
                }
            }
            if let error = error {
                print("[SpeechRecognizer] Recognition error: \(error)")
                Task { @MainActor in self.finishListening() }
            } else if result?.isFinal == true {
                Task { @MainActor in self.finishListening() }
            }
        }

        // Max time safety valve
        silenceTimer = Timer.scheduledTimer(withTimeInterval: maxListenTime, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishListening() }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishListening() }
        }
    }

    private func finishListening() {
        let text = transcribedText
        stopListening()
        onComplete?(text)
        onComplete = nil
    }

    enum SpeechError: Error { case invalidFormat }
}
