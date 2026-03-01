import SwiftUI

@main
struct RAMLtoISAApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 620, height: 520)

        Settings {
            SettingsView()
        }
    }
}
