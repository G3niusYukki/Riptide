import SwiftUI
import Riptide

@main
struct RiptideApp: App {
    @State private var appVM = AppViewModel()
    @State private var statusBar = StatusBarController()

    var body: some Scene {
        WindowGroup {
            MainTabView(vm: appVM)
                .preferredColorScheme(.dark)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    statusBar.setup(vm: appVM)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)
    }
}
