// TakeManager.swift
// ScenePartner — Take browser, thumbnail generation, and selection.

import Foundation
import AVFoundation
import UIKit
import SwiftUI

struct Take: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let number: Int
    let scriptID: UUID
    let sceneIndex: Int
    let createdAt: Date
    var isHero: Bool = false
    var thumbnail: UIImage? = nil

    var displayName: String { "Take \(number)" }
    var formattedDuration: String {
        // Read duration from file metadata without async call
        let asset = AVURLAsset(url: url)
        var secs = 0
        // timeRange from tracks is synchronous on iOS 16+
        if let track = asset.tracks(withMediaType: .video).first {
            let dur = track.timeRange.duration
            if dur.isValid && !dur.isIndefinite {
                secs = Int(dur.seconds)
            }
        }
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

@MainActor
final class TakeManager: ObservableObject {

    @Published private(set) var takes: [Take] = []
    @Published private(set) var heroTakeID: UUID? = nil

    private let scriptID: UUID
    private let sceneIndex: Int

    init(scriptID: UUID, sceneIndex: Int, savedURLs: [URL]) {
        self.scriptID = scriptID
        self.sceneIndex = sceneIndex
        self.takes = savedURLs.enumerated().map { index, url in
            Take(id: UUID(), url: url, number: index + 1,
                 scriptID: scriptID, sceneIndex: sceneIndex,
                 createdAt: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date())
        }
        loadThumbnails()
    }

    func addTake(url: URL) {
        let take = Take(id: UUID(), url: url, number: takes.count + 1,
                        scriptID: scriptID, sceneIndex: sceneIndex, createdAt: Date())
        takes.append(take)
        generateThumbnail(for: take)
    }

    func setHero(_ take: Take) {
        heroTakeID = take.id
    }

    func deleteTake(_ take: Take) {
        try? FileManager.default.removeItem(at: take.url)
        takes.removeAll { $0.id == take.id }
        // Re-number
        for i in takes.indices { takes[i] = Take(
            id: takes[i].id, url: takes[i].url, number: i + 1,
            scriptID: scriptID, sceneIndex: sceneIndex,
            createdAt: takes[i].createdAt, isHero: takes[i].isHero,
            thumbnail: takes[i].thumbnail)
        }
    }

    // MARK: - Thumbnails

    private func loadThumbnails() {
        for take in takes { generateThumbnail(for: take) }
    }

    private func generateThumbnail(for take: Take) {
        let url = take.url
        let id = take.id
        Task.detached {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let thumb = UIImage(cgImage: cgImage)
                await MainActor.run {
                    if let idx = self.takes.firstIndex(where: { $0.id == id }) {
                        self.takes[idx].thumbnail = thumb
                    }
                }
            }
        }
    }
}
