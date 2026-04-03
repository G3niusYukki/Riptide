import SwiftUI
import Riptide

@main
struct RiptideApp: App {
    @State private var appVM = AppViewModel()
    @State private var statusBarController = StatusBarController()

    var body: some Scene {
        WindowGroup {
            MainTabView(vm: appVM)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") {
                    NSApp.sendAction(Selector(("showPreferencesWindow")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
