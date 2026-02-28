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

    init() { loadAll() }

    @discardableResult
    func createScript(title: String, rawText: String) -> Script {
        var script = parser.parse(rawText: rawText, title: title)
        script = Script(id: script.id, title: title.isEmpty ? "Untitled Script" : title,
                        rawText: rawText, lines: script.lines, scenes: script.scenes,
                        characters: script.characters, createdAt: Date(), updatedAt: Date())
        save(script); scripts.append(script)
        scripts.sort { $0.updatedAt > $1.updatedAt }
        return script
    }

    func delete(_ script: Script) {
        try? fileManager.removeItem(at: fileURL(for: script.id))
        scripts.removeAll { $0.id == script.id }
    }

    private func save(_ script: Script) {
        if let data = try? JSONEncoder().encode(script) {
            try? data.write(to: fileURL(for: script.id), options: .atomic)
        }
    }

    private func loadAll() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: documentsURL, includingPropertiesForKeys: nil) else { return }
        scripts = urls.filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Script.self, from: data)
            }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
