import SwiftUI
import SwiftData

@main struct DocAIApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: Document.self)
    }
}
