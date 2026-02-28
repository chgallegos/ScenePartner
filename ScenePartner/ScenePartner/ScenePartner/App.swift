// App.swift
import SwiftUI

@main
struct ScenePartnerMain: App {

    @State private var scriptStore = ScriptStore()
    @State private var connectivity = ConnectivityMonitor()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scriptStore)
                .environment(connectivity)
                .environment(settings)
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
