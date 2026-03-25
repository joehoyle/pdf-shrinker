import SwiftUI

@main
struct PDFShrinkerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)
    }
}
