// App.swift
// ScenePartner — App entry point.

import SwiftUI

@main
struct ScenePartnerMain: App {

    @StateObject private var scriptStore = ScriptStore()
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(scriptStore)
                .environmentObject(connectivity)
                .environmentObject(settings)
        }
    }
}

struct RootView: View {
    var body: some View {
        NavigationStack {
            ScriptListView()
        }
    }
}
