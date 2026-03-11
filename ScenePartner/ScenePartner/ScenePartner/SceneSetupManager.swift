// SceneSetupManager.swift
// Manages the "scene setup" phase: user records partner lines,
// ElevenLabs Voice Changer converts them to a different voice.
// Converted audio is saved locally and reused across rehearsal sessions.

import Foundation
import AVFoundation
import Combine

// MARK: - Models

struct SceneSetup: Codable {
    var scriptID: UUID
    var characterName: String           // The partner character this setup is for
    var convertedAudioPaths: [Int: String]  // lineIndex → local file path
    var createdAt: Date

    init(scriptID: UUID, characterName: String) {
        self.scriptID = scriptID
        self.characterName = characterName
        self.convertedAudioPaths = [:]
        self.createdAt = Date()
    }

    var isComplete: Bool { !convertedAudioPaths.isEmpty }
}

enum SetupLineStatus {
    case pending
    case recording
    case recorded
    case converting
    case ready
    case failed(String)
}

// MARK: - SceneSetupManager

@MainActor
final class SceneSetupManager: NSObject, ObservableObject {

    // Published state
    @Published private(set) var lineStatuses: [Int: SetupLineStatus] = [:]
    @Published private(set) var isRecording = false
    @Published private(set) var currentRecordingIndex: Int? = nil
    @Published private(set) var audioLevel: Float = 0.0
    @Published var setup: SceneSetup

    // The partner lines we need to record
    let partnerLines: [Line]
    let characterName: String

    private let elevenLabsAPIKey: String
    private let targetVoiceID: String  // The voice to convert TO

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var tempRecordingURL: URL?

    // MARK: - Init

    init(script: Script, characterName: String, elevenLabsAPIKey: String, targetVoiceID: String) {
        self.characterName = characterName
        self.elevenLabsAPIKey = elevenLabsAPIKey
        self.targetVoiceID = targetVoiceID
        self.partnerLines = script.lines.filter {
            $0.type == .dialogue && $0.speaker?.uppercased() == characterName.uppercased()
        }
        self.setup = SceneSetup(scriptID: script.id, characterName: characterName)

        super.init()

        // Load any previously saved setup
        if let saved = Self.loadSetup(scriptID: script.id, characterName: characterName) {
            self.setup = saved
            // Mark already-converted lines as ready
            for (index, _) in saved.convertedAudioPaths {
                lineStatuses[index] = .ready
            }
        }

        // Mark remaining as pending
        for line in partnerLines {
            if lineStatuses[line.index] == nil {
                lineStatuses[line.index] = .pending
            }
        }
    }

    // MARK: - Recording

    func startRecording(lineIndex: Int) {
        guard !isRecording else { return }

        let url = tempAudioURL(for: lineIndex)
        tempRecordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            currentRecordingIndex = lineIndex
            lineStatuses[lineIndex] = .recording

            // Level metering timer
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.audioRecorder?.updateMeters()
                    let power = self?.audioRecorder?.averagePower(forChannel: 0) ?? -60
                    // Convert dB to 0-1 range
                    let normalized = max(0, (power + 60) / 60)
                    self?.audioLevel = normalized
                }
            }
        } catch {
            lineStatuses[lineIndex] = .failed("Could not start recording: \(error.localizedDescription)")
        }
    }

    func stopRecordingAndConvert(lineIndex: Int) {
        guard isRecording, let recordingURL = tempRecordingURL else { return }

        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        currentRecordingIndex = nil
        audioLevel = 0.0

        try? AVAudioSession.sharedInstance().setActive(false)

        lineStatuses[lineIndex] = .recorded

        // Convert via ElevenLabs Voice Changer
        Task {
            await convertRecording(at: recordingURL, lineIndex: lineIndex)
        }
    }

    func cancelRecording(lineIndex: Int) {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        currentRecordingIndex = nil
        audioLevel = 0.0
        lineStatuses[lineIndex] = .pending
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Voice Conversion

    private func convertRecording(at url: URL, lineIndex: Int) async {
        lineStatuses[lineIndex] = .converting

        guard !elevenLabsAPIKey.isEmpty else {
            print("[SceneSetup] ⚠️ No API key — using raw recording (no voice change)")
            let outputPath = saveRawRecording(from: url, lineIndex: lineIndex)
            setup.convertedAudioPaths[lineIndex] = outputPath
            lineStatuses[lineIndex] = .ready
            saveSetup()
            return
        }

        // Log the raw recording info
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int {
            let duration = Double(size) / (44100 * 1 * 2)  // rough estimate
            print("[SceneSetup] 🎤 Raw recording: \(size) bytes (~\(String(format: "%.1f", duration))s) at \(url.lastPathComponent)")
        }

        do {
            print("[SceneSetup] 📡 Sending to ElevenLabs STS API...")
            let convertedData = try await callVoiceChangerAPI(audioURL: url)
            let outputURL = convertedAudioURL(for: lineIndex)
            try convertedData.write(to: outputURL)
            setup.convertedAudioPaths[lineIndex] = outputURL.lastPathComponent  // filename only
            lineStatuses[lineIndex] = .ready
            saveSetup()
            print("[SceneSetup] ✅ Line \(lineIndex) CONVERTED — \(convertedData.count) bytes saved to \(outputURL.lastPathComponent)")
            print("[SceneSetup] 🎭 This line will play as voice-converted audio during rehearsal")
        } catch {
            print("[SceneSetup] ❌ CONVERSION FAILED line \(lineIndex): \(error)")
            print("[SceneSetup] ⚠️ Falling back to RAW recording — voice will NOT be changed for this line")
            let outputPath = saveRawRecording(from: url, lineIndex: lineIndex)
            setup.convertedAudioPaths[lineIndex] = outputPath
            lineStatuses[lineIndex] = .ready
            saveSetup()
        }
    }

    private func callVoiceChangerAPI(audioURL: URL) async throws -> Data {
        // Use a voice well-suited for emotional conversion
        // Daniel (onwK4e9ZLuTAKqWW03F9) for male, Bella (EXAVITQu4vr4xnSDxMaL) for female
        let conversionVoiceID = targetVoiceID.isEmpty ? "IKne3meq5aSn9XLyUdCD" : targetVoiceID
        let apiURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-speech/\(conversionVoiceID)/stream")!

        print("""
        [SceneSetup] 🌐 API Call:
          URL: \(apiURL)
          Voice ID: \(conversionVoiceID)
          Model: eleven_multilingual_sts_v2
          stability: 0.30, similarity_boost: 0.60, style: 0.0
          API key ending: ...\(elevenLabsAPIKey.suffix(6))
        """)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        print("[SceneSetup] Audio size: \(audioData.count) bytes")

        var body = Data()

        // Audio file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // eleven_multilingual_sts_v2 preserves emotion far better than english v2
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("eleven_multilingual_sts_v2\r\n".data(using: .utf8)!)

        // stability: how stable the voice is (lower = more expressive)
        // similarity_boost: how closely to match target voice vs preserve YOUR delivery
        //   0.65 = good balance — voice sounds different but your emotion comes through
        // style: 0 = don't add artificial style on top of your performance
        // use_speaker_boost: false = don't over-process, keep it natural
        let voiceSettings = "{\"stability\":0.30,\"similarity_boost\":0.60,\"style\":0.0,\"use_speaker_boost\":false}"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"voice_settings\"\r\n\r\n".data(using: .utf8)!)
        body.append(voiceSettings.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Remove background noise from iPad mic recording
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"remove_background_noise\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VoiceConversionError.invalidResponse }

        print("[SceneSetup] Voice Changer API: HTTP \(http.statusCode), \(data.count) bytes returned")

        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[SceneSetup] ❌ API error \(http.statusCode): \(msg)")
            throw VoiceConversionError.apiError(http.statusCode, msg)
        }

        return data
    }

    // MARK: - Playback helper

    func resolvedAudioURL(for lineIndex: Int) -> URL? {
        guard let filename = setup.convertedAudioPaths[lineIndex] else { return nil }
        // Always reconstruct full path at runtime — never trust stored absolute paths
        // which become stale after reinstalls or app container UUID changes
        let url = Self.setupDirectory(scriptID: setup.scriptID, characterName: characterName)
            .appendingPathComponent(filename)
        return url
    }

    // MARK: - Computed

    var allLinesReady: Bool {
        partnerLines.allSatisfy { line in
            if case .ready = lineStatuses[line.index] ?? .pending { return true }
            return false
        }
    }

    var readyCount: Int {
        partnerLines.filter { line in
            if case .ready = lineStatuses[line.index] ?? .pending { return true }
            return false
        }.count
    }

    // MARK: - Persistence

    private func saveRawRecording(from url: URL, lineIndex: Int) -> String {
        let outputURL = convertedAudioURL(for: lineIndex)
        try? FileManager.default.copyItem(at: url, to: outputURL)
        return outputURL.lastPathComponent  // store filename only
    }

    private func tempAudioURL(for lineIndex: Int) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scene_setup_temp_\(lineIndex).m4a")
    }

    private func convertedAudioURL(for lineIndex: Int) -> URL {
        Self.setupDirectory(scriptID: setup.scriptID, characterName: characterName)
            .appendingPathComponent("line_\(lineIndex).mp3")
    }

    private static func setupDirectory(scriptID: UUID, characterName: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SceneSetups/\(scriptID.uuidString)/\(characterName)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func setupMetaURL(scriptID: UUID, characterName: String) -> URL {
        setupDirectory(scriptID: scriptID, characterName: characterName)
            .appendingPathComponent("setup.json")
    }

    // Resolve a stored filename back to a full URL at runtime
    static func resolveAudioURL(scriptID: UUID, characterName: String, lineIndex: Int) -> URL {
        setupDirectory(scriptID: scriptID, characterName: characterName)
            .appendingPathComponent("line_\(lineIndex).mp3")
    }


    /// Deletes all files and resets in-memory state completely
    func resetAll() {
        // Stop any active recording first
        if isRecording {
            levelTimer?.invalidate()
            levelTimer = nil
            audioRecorder?.stop()
            audioRecorder = nil
            isRecording = false
            currentRecordingIndex = nil
            audioLevel = 0
            try? AVAudioSession.sharedInstance().setActive(false)
        }
        // Delete all files on disk
        Self.deleteSetup(scriptID: setup.scriptID, characterName: characterName)
        // Reset all in-memory state
        setup = SceneSetup(scriptID: setup.scriptID, characterName: characterName)
        for line in partnerLines {
            lineStatuses[line.index] = .pending
        }
        print("[SceneSetup] ✅ Reset complete for \(characterName) — all lines marked pending")
    }

    func saveSetup() {
        let url = Self.setupMetaURL(scriptID: setup.scriptID, characterName: characterName)
        if let data = try? JSONEncoder().encode(setup) {
            try? data.write(to: url)
            print("[SceneSetup] 💾 Saved setup.json for \(characterName)")
        }
    }

    static func loadSetup(scriptID: UUID, characterName: String) -> SceneSetup? {
        let url = setupMetaURL(scriptID: scriptID, characterName: characterName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SceneSetup.self, from: data)
    }

    static func deleteSetup(scriptID: UUID, characterName: String) {
        let dir = setupDirectory(scriptID: scriptID, characterName: characterName)
        do {
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
                print("[SceneSetup] 🗑️ Deleted all recordings for \(characterName)")
            } else {
                print("[SceneSetup] ⚠️ Nothing to delete for \(characterName) — directory didn't exist")
            }
        } catch {
            print("[SceneSetup] ❌ Failed to delete recordings for \(characterName): \(error)")
        }
    }

    enum VoiceConversionError: Error {
        case invalidResponse
        case apiError(Int, String)
    }
}
