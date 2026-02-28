// CameraEngine.swift
import AVFoundation
import SwiftUI
import Photos

final class CameraEngine: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published State
    @Published private(set) var isRecording = false
    @Published private(set) var isSessionRunning = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var countdownValue: Int? = nil
    @Published private(set) var permissionsGranted = false
    @Published private(set) var currentTake: Int = 1
    @Published var isFrontCamera = true

    // MARK: - Capture Session
    let session = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.scenepartner.camera", qos: .userInitiated)

    // MARK: - Asset Writer
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var sessionAtSourceTime: CMTime?
    private var outputURL: URL?
    private var durationTimer: Timer?

    // MARK: - State
    private var scriptID: UUID = UUID()
    private var sceneIndex: Int = 0

    override init() {
        super.init()
        requestPermissions()
    }

    // MARK: - Permissions

    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] audioGranted in
                guard audioGranted else { return }
                DispatchQueue.main.async {
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

        // Video
        let position: AVCaptureDevice.Position = isFrontCamera ? .front : .back
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        }

        // Audio
        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(input) {
            session.addInput(input)
        }

        // Video output
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            if let conn = videoDataOutput.connection(with: .video) {
                conn.isVideoMirrored = isFrontCamera
                if conn.isVideoRotationAngleSupported(90) {
                    conn.videoRotationAngle = 90
                }
            }
        }

        // Audio output
        audioDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        }

        session.commitConfiguration()
        session.startRunning()

        DispatchQueue.main.async { self.isSessionRunning = true }
    }

    func flipCamera() {
        let newFront = !isFrontCamera
        DispatchQueue.main.async { self.isFrontCamera = newFront }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old) }

            let pos: AVCaptureDevice.Position = newFront ? .front : .back
            if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
               let input = try? AVCaptureDeviceInput(device: dev),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
            }
            if let conn = self.videoDataOutput.connection(with: .video) {
                conn.isVideoMirrored = newFront
                if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            }
            self.session.commitConfiguration()
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
            DispatchQueue.main.async {
                if let v = self.countdownValue, v > 1 {
                    self.countdownValue = v - 1
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

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            print("[CameraEngine] ❌ Failed to create writer"); return
        }
        assetWriter = writer

        let vs: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080, AVVideoHeightKey: 1920
        ]
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: vs)
        videoWriterInput?.expectsMediaDataInRealTime = true

        let as_: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]
        audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: as_)
        audioWriterInput?.expectsMediaDataInRealTime = true

        if let vi = videoWriterInput, writer.canAdd(vi) { writer.add(vi) }
        if let ai = audioWriterInput, writer.canAdd(ai) { writer.add(ai) }

        sessionAtSourceTime = nil
        writer.startWriting()

        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingDuration = 0
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingDuration += 0.1
            }
        }
        print("[CameraEngine] 🔴 Recording: \(url.lastPathComponent)")
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else { completion(nil); return }

        DispatchQueue.main.async {
            self.isRecording = false
            self.durationTimer?.invalidate()
        }

        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        let url = outputURL

        assetWriter?.finishWriting {
            print("[CameraEngine] ✅ Saved: \(url?.lastPathComponent ?? "")")
            DispatchQueue.main.async { completion(url) }
        }
    }

    // MARK: - File Management

    private func takeURL(scriptID: UUID, sceneIndex: Int, take: Int) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(scriptID.uuidString)_s\(sceneIndex)_t\(take).mp4")
    }

    func savedTakes(scriptID: UUID, sceneIndex: Int) -> [URL] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Takes")
        let prefix = "\(scriptID.uuidString)_s\(sceneIndex)_t"
        return (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey]
        ))?.filter { $0.lastPathComponent.hasPrefix(prefix) }
           .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    func nextTakeNumber(scriptID: UUID, sceneIndex: Int) -> Int {
        savedTakes(scriptID: scriptID, sceneIndex: sceneIndex).count + 1
    }

    func deleteTake(at url: URL) { try? FileManager.default.removeItem(at: url) }

    func exportToPhotoLibrary(url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }; return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if let error { print("[CameraEngine] Export error: \(error)") }
                DispatchQueue.main.async { completion(success) }
            }
        }
    }
}

// MARK: - Sample Buffer Delegate

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let writer = assetWriter, writer.status == .writing else { return }

        let isVideo = output is AVCaptureVideoDataOutput

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
