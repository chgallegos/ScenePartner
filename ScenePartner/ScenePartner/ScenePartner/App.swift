// App.swift
// Note: Xcode 26 beta / Swift 6 requires concrete return type instead of 'some Scene'
import SwiftUI

@main
struct ScenePartnerMain: App {
    var body: WindowGroup<AppRootView> {
        WindowGroup {
            AppRootView()
        }
    }
}

struct AppRootView: View {
    @StateObject private var scriptStore = ScriptStore()
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var settings = AppSettings()

    var body: some View {
        NavigationStack {
            ScriptListView()
        }
        .environmentObject(scriptStore)
        .environmentObject(connectivity)
        .environmentObject(settings)
    }
}
