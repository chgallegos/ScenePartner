// App.swift
// ScenePartner — App entry point. Injects shared services into the SwiftUI environment.

import SwiftUI

@main
struct ScenePartnerApp: App {

    // Shared singletons injected via environment
    @StateObject private var scriptStore = ScriptStore()
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scriptStore)
                .environmentObject(connectivity)
                .environmentObject(settings)
        }
    }
}

// MARK: - ContentView (root navigator)

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScriptListView()
        }
    }
}
