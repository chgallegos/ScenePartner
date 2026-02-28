// App.swift
// ScenePartner — App entry point. Injects shared services into the SwiftUI environment.

import SwiftUI

@main
struct ScenePartnerMain: App {

    @StateObject private var scriptStore = ScriptStore()
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScriptListView()
            }
            .environmentObject(scriptStore)
            .environmentObject(connectivity)
            .environmentObject(settings)
        }
    }
}
