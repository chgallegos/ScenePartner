// App.swift
import SwiftUI

@main
struct ScenePartnerMain: App {
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

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScriptListView()
        }
    }
}
