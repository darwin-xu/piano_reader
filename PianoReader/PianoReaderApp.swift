import SwiftUI

@main
struct PianoReaderApp: App {
    @StateObject private var viewModel = RecognitionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}