// SpeechRecognizer.swift
import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {

    @Published private(set) var isListening = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var permissionGranted = false
    @Published private(set) var audioLevel: Float = 0  // 0.0-1.0 for UI meter

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var onComplete: ((String) -> Void)?
    private var hasHeardSpeech = false

    // After speech detected, wait this long after last word before advancing
    private let silenceAfterSpeech: TimeInterval = 0.8
    // If no speech heard at all within this time, give up
    private let maxSilenceBeforeSpeech: TimeInterval = 15.0

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestPermission()
    }

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.permissionGranted = status == .authorized
                print("[SpeechRecognizer] Permission: \(status.rawValue)")
            }
        }
    }

    func startListening(completion: @escaping (String) -> Void) {
        guard permissionGranted else {
            print("[SpeechRecognizer] ⚠️ No permission — requesting")
            requestPermission()
            return
        }
        guard !isListening else {
            print("[SpeechRecognizer] Already listening")
            return
        }

        print("[SpeechRecognizer] 🎤 Starting...")
        onComplete = completion
        transcribedText = ""
        hasHeardSpeech = false

        do {
            try startAudioEngine()
            isListening = true
            print("[SpeechRecognizer] ✅ Listening")

            // Start max-silence timer — give up if user doesn't speak
            silenceTimer = Timer.scheduledTimer(
                withTimeInterval: maxSilenceBeforeSpeech, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    print("[SpeechRecognizer] ⏱️ Max silence reached — giving up")
                    self?.finishListening()
                }
            }
        } catch {
            print("[SpeechRecognizer] ❌ Failed to start: \(error)")
            isListening = false
            // Don't auto-advance on failure — let user tap manually
        }
    }

    func stopListening() {
        guard isListening || audioEngine.isRunning else { return }
        print("[SpeechRecognizer] 🛑 Stopping")
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
        audioLevel = 0

        // Restore playback session
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func startAudioEngine() throws {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        // Server recognition — more reliable than on-device
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0 && nativeFormat.channelCount > 0 else {
            print("[SpeechRecognizer] ❌ Invalid audio format: sr=\(nativeFormat.sampleRate) ch=\(nativeFormat.channelCount)")
            throw SpeechError.invalidFormat
        }

        print("[SpeechRecognizer] Audio format: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Calculate audio level for UI feedback
            let level = self?.calculateLevel(buffer: buffer) ?? 0
            Task { @MainActor in
                self?.audioLevel = level
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        print("[SpeechRecognizer] Audio engine started")

        // Speech recognition callback
        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty {
                    Task { @MainActor in
                        print("[SpeechRecognizer] 💬 Heard: \"\(text)\"")
                        self.transcribedText = text
                        self.hasHeardSpeech = true
                        self.resetSilenceTimer()
                    }
                }
            }

            if let error = error {
                // Code 1110 = no speech detected — normal, not an error
                let nsError = error as NSError
                if nsError.code != 1110 {
                    print("[SpeechRecognizer] ⚠️ Error \(nsError.code): \(error.localizedDescription)")
                }
                Task { @MainActor in self.finishListening() }
            } else if result?.isFinal == true {
                Task { @MainActor in self.finishListening() }
            }
        }
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength { sum += abs(channelData[i]) }
        let avg = sum / Float(frameLength)
        return min(avg * 20, 1.0)  // Scale to 0-1
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceAfterSpeech, repeats: false) { [weak self] _ in
            Task { @MainActor in
                print("[SpeechRecognizer] ⏱️ Silence detected after speech — finishing")
                self?.finishListening()
            }
        }
    }

    private func finishListening() {
        let text = transcribedText
        print("[SpeechRecognizer] ✅ Finished. Text: \"\(text)\"")
        stopListening()
        onComplete?(text)
        onComplete = nil
    }

    enum SpeechError: Error { case invalidFormat }
}
