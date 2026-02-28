// ScriptListView.swift
// ScenePartner — Home screen listing saved scripts with add/delete.

import SwiftUI
import UniformTypeIdentifiers

struct ScriptListView: View {

    @EnvironmentObject private var store: ScriptStore
    @EnvironmentObject private var connectivity: ConnectivityMonitor

    @State private var showAddSheet = false
    @State private var showImportPicker = false
    @State private var scriptToDelete: Script? = nil

    var body: some View {
        Group {
            if store.scripts.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.scripts) { script in
                        NavigationLink(value: script) {
                            ScriptRowView(script: script)
                        }
                    }
                    .onDelete { offsets in
                        offsets.forEach { store.delete(store.scripts[$0]) }
                    }
                }
            }
        }
        .navigationTitle("My Scripts")
        .navigationDestination(for: Script.self) { script in
            RoleSelectionView(script: script)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Paste Script", systemImage: "doc.text") {
                        showAddSheet = true
                    }
                    Button("Import .txt File", systemImage: "folder") {
                        showImportPicker = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddScriptView()
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .overlay(alignment: .bottom) {
            if connectivity.isConnected {
                EmptyView()
            } else {
                offlineBanner
            }
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No scripts yet")
                .font(.title2.weight(.semibold))
            Text("Paste a script or import a .txt file to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Add Script") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var offlineBanner: some View {
        Label("Offline — core rehearsal available", systemImage: "wifi.slash")
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 8)
    }

    // MARK: - File Import

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let title = url.deletingPathExtension().lastPathComponent
            store.createScript(title: title, rawText: text)
        }
    }
}

// MARK: - ScriptRowView

struct ScriptRowView: View {
    let script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(script.title)
                .font(.headline)
            HStack(spacing: 12) {
                Label("\(script.lines.filter { $0.type == .dialogue }.count) lines",
                      systemImage: "text.bubble")
                Label("\(script.scenes.count) scenes",
                      systemImage: "film")
                Label("\(script.characters.count) chars",
                      systemImage: "person.2")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AddScriptView

struct AddScriptView: View {
    @EnvironmentObject private var store: ScriptStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var rawText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Romeo & Juliet Act II", text: $title)
                }
                Section("Script") {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 300)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("New Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = title.isEmpty ? "Untitled" : title
                        store.createScript(title: t, rawText: rawText)
                        dismiss()
                    }
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
