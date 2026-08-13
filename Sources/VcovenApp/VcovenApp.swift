import SwiftUI

@main
struct VcovenApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 640, height: 500)
    }
}
