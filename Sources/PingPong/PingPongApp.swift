import SwiftUI

@main
struct PingPongApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1120, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Start or Stop Test") {
                    if viewModel.session.state.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                }
                .keyboardShortcut(.space, modifiers: [.command])
            }
        }
    }
}
