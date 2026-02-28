// ScriptStore.swift
// ScenePartner — Manages saving, loading, and deleting scripts from local storage.
//
// Storage strategy:
//   • One JSON file per script in the app's Documents directory
//   • File name format: <script.id>.json
//   • No iCloud sync by default (privacy-first)

import Foundation
import Combine

@MainActor
final class ScriptStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var scripts: [Script] = []

    // MARK: - Private

    private let parser = ScriptParser()
    private let fileManager = FileManager.default

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func fileURL(for id: UUID) -> URL {
        documentsURL.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Init

    init() {
        loadAll()
    }

    // MARK: - CRUD

    /// Parse raw text into a new Script and persist it.
    @discardableResult
    func createScript(title: String, rawText: String) -> Script {
        var script = parser.parse(rawText: rawText, title: title)
        script = Script(
            id: script.id,
            title: title.isEmpty ? "Untitled Script" : title,
            rawText: rawText,
            lines: script.lines,
            scenes: script.scenes,
            characters: script.characters,
            createdAt: Date(),
            updatedAt: Date()
        )
        save(script)
        scripts.append(script)
        scripts.sort { $0.updatedAt > $1.updatedAt }
        return script
    }

    func update(_ script: Script) {
        var updated = script
        updated = Script(
            id: script.id,
            title: script.title,
            rawText: script.rawText,
            lines: script.lines,
            scenes: script.scenes,
            characters: script.characters,
            createdAt: script.createdAt,
            updatedAt: Date()
        )
        save(updated)
        if let idx = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[idx] = updated
        }
    }

    func delete(_ script: Script) {
        let url = fileURL(for: script.id)
        try? fileManager.removeItem(at: url)
        scripts.removeAll { $0.id == script.id }
    }

    // MARK: - Persistence

    private func save(_ script: Script) {
        let url = fileURL(for: script.id)
        do {
            let data = try JSONEncoder().encode(script)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[ScriptStore] Save failed: \(error)")
        }
    }

    private func loadAll() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: documentsURL, includingPropertiesForKeys: nil
        ) else { return }

        let jsonURLs = urls.filter { $0.pathExtension == "json" }
        scripts = jsonURLs.compactMap { url -> Script? in
            guard let data = try? Data(contentsOf: url),
                  let script = try? JSONDecoder().decode(Script.self, from: data)
            else { return nil }
            return script
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
