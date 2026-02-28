// App.swift
import SwiftUI

// Using a single shared AppState object avoids Xcode 26 beta @StateObject/@main conformance issues
final class AppState: ObservableObject {
    let scriptStore = ScriptStore()
    let connectivity = ConnectivityMonitor()
    let settings = AppSettings()
}

@main
struct ScenePartnerMain: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState.scriptStore)
                .environmentObject(appState.connectivity)
                .environmentObject(appState.settings)
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScriptListView()
        }
    }
}
