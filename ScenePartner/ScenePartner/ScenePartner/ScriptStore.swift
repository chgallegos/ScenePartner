// ScriptStore.swift
import Foundation
import Combine

final class ScriptStore: ObservableObject {

    @Published private(set) var scripts: [Script] = []

    private let parser = ScriptParser()
    private let fileManager = FileManager.default

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func fileURL(for id: UUID) -> URL {
        documentsURL.appendingPathComponent("\(id.uuidString).json")
    }

    init() {
        loadAll()
    }

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
        let updated = Script(
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
        try? fileManager.removeItem(at: fileURL(for: script.id))
        scripts.removeAll { $0.id == script.id }
    }

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

        scripts = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Script? in
                guard let data = try? Data(contentsOf: url),
                      let script = try? JSONDecoder().decode(Script.self, from: data)
                else { return nil }
                return script
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
