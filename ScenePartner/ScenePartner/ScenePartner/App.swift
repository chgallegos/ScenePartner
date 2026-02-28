// App.swift
import SwiftUI

// Shared app-wide state held outside the App struct to avoid Xcode 26 beta @StateObject issues
private let sharedScriptStore = ScriptStore()
private let sharedConnectivity = ConnectivityMonitor()
private let sharedSettings = AppSettings()

@main
struct ScenePartnerMain: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScriptListView()
            }
            .environmentObject(sharedScriptStore)
            .environmentObject(sharedConnectivity)
            .environmentObject(sharedSettings)
        }
    }
}
