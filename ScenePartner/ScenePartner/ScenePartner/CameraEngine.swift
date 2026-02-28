// CameraEngine.swift
// ScenePartner — Manages camera preview, recording, and take storage.
// Uses AVCaptureSession + AVAssetWriter to record video + audio simultaneously.

import AVFoundation
import SwiftUI
import Photos

@MainActor
final class CameraEngine: NSObject, ObservableObject {

    // MARK: - Published State
    @Published private(set) var isRecording = false
    @Published private(set) var isSessionRunning = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var countdownValue: Int? = nil    // 3, 2, 1, nil = recording
    @Published private(set) var permissionsGranted = false
    @Published private(set) var currentTake: Int = 1
    @Published var isFrontCamera = true

    // MARK: - Capture Session
    let session = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.scenepartner.camera")

    // MARK: - Asset Writer (recording)
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var sessionAtSourceTime: CMTime?
    private var outputURL: URL?
    private var durationTimer: Timer?

    // MARK: - Take Storage
    private var scriptID: UUID = UUID()
    private var sceneIndex: Int = 0

    // MARK: - Init

    override init() {
        super.init()
        requestPermissions()
    }

    // MARK: - Permissions

    func requestPermissions() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if cameraStatus == .authorized && micStatus == .authorized {
            permissionsGranted = true
            setupSession()
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else { return }
                Task { @MainActor in
                    self?.permissionsGranted = true
                    self?.setupSession()
                }
            }
        }
    }

    // MARK: - Session Setup

    private func setupSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Video input
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: device) {
            if session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            }
        }

        // Audio input
        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic) {
            if session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
        }

        // Video output
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            // Mirror front camera
            if let connection = videoDataOutput.connection(with: .video) {
                connection.isVideoMirrored = isFrontCamera
                connection.videoRotationAngle = 90
            }
        }

        // Audio output
        audioDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        }

        session.commitConfiguration()

        session.startRunning()
        Task { @MainActor in self.isSessionRunning = true }
    }

    func flipCamera() {
        isFrontCamera.toggle()
        sessionQueue.async { [weak self] in
            self?.session.beginConfiguration()
            if let input = self?.videoInput { self?.session.removeInput(input) }

            let position: AVCaptureDevice.Position = (self?.isFrontCamera == true) ? .front : .back
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: device),
               self?.session.canAddInput(input) == true {
                self?.session.addInput(input)
                self?.videoInput = input
            }

            if let connection = self?.videoDataOutput.connection(with: .video) {
                connection.isVideoMirrored = self?.isFrontCamera == true
                connection.videoRotationAngle = 90
            }
            self?.session.commitConfiguration()
        }
    }

    // MARK: - Countdown + Record

    func startCountdownAndRecord(scriptID: UUID, sceneIndex: Int, takeNumber: Int) {
        self.scriptID = scriptID
        self.sceneIndex = sceneIndex
        self.currentTake = takeNumber
        countdownValue = 3

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                if let current = self.countdownValue, current > 1 {
                    self.countdownValue = current - 1
                } else {
                    self.countdownValue = nil
                    timer.invalidate()
                    self.startRecording()
                }
            }
        }
    }

    private func startRecording() {
        let url = takeURL(scriptID: scriptID, sceneIndex: sceneIndex, take: currentTake)
        outputURL = url

        do {
            assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            print("[CameraEngine] ❌ Failed to create AssetWriter: \(error)")
            return
        }

        // Video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920
        ]
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true

        // Audio settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]
        audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioWriterInput?.expectsMediaDataInRealTime = true

        if let vi = videoWriterInput, assetWriter?.canAdd(vi) == true { assetWriter?.add(vi) }
        if let ai = audioWriterInput, assetWriter?.canAdd(ai) == true { assetWriter?.add(ai) }

        sessionAtSourceTime = nil
        assetWriter?.startWriting()

        isRecording = true
        recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordingDuration += 0.1 }
        }
        print("[CameraEngine] 🔴 Recording started: \(url.lastPathComponent)")
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else { completion(nil); return }
        isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil

        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()

        assetWriter?.finishWriting { [weak self] in
            guard let self else { return }
            let url = self.outputURL
            print("[CameraEngine] ✅ Recording saved: \(url?.lastPathComponent ?? "unknown")")
            Task { @MainActor in completion(url) }
        }
    }

    // MARK: - File Management

    private func takeURL(scriptID: UUID, sceneIndex: Int, take: Int) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(scriptID.uuidString)_scene\(sceneIndex)_take\(take).mp4")
    }

    func savedTakes(scriptID: UUID, sceneIndex: Int) -> [URL] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Takes")
        let prefix = "\(scriptID.uuidString)_scene\(sceneIndex)_take"
        return (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey]
        ))?.filter { $0.lastPathComponent.hasPrefix(prefix) }
           .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    func nextTakeNumber(scriptID: UUID, sceneIndex: Int) -> Int {
        savedTakes(scriptID: scriptID, sceneIndex: sceneIndex).count + 1
    }

    func deleteTake(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Export to Camera Roll

    func exportToPhotoLibrary(url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                Task { @MainActor in completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if let error { print("[CameraEngine] Export error: \(error)") }
                Task { @MainActor in completion(success) }
            }
        }
    }
}

// MARK: - Sample Buffer Delegate

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let writer = assetWriter,
              writer.status == .writing else { return }

        let isVideo = output is AVCaptureVideoDataOutput

        // Set start time on first sample
        if sessionAtSourceTime == nil {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            sessionAtSourceTime = time
            writer.startSession(atSourceTime: time)
        }

        if isVideo, let input = videoWriterInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        } else if !isVideo, let input = audioWriterInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
