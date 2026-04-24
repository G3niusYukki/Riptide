import SwiftUI
import AppKit
import Riptide

// Shared coordinator — holds the main window reference for the entire app
@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()
    var mainWindow: NSWindow?

    private init() {}
}

@main
struct RiptideApp: App {
    @State private var appVM = AppViewModel()
    @State private var statusBar: StatusBarController?

    var body: some SwiftUI.Scene {
        WindowGroup {
            MainTabView(vm: appVM)
                .preferredColorScheme(.dark)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    guard self.statusBar == nil else { return }

                    // Center window on screen
                    if let window = NSApp.windows.first,
                       let screen = NSScreen.main ?? NSScreen.screens.first {
                        let screenFrame = screen.visibleFrame
                        let windowSize = window.frame.size
                        let centerX = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
                        let centerY = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
                        window.setFrameOrigin(NSPoint(x: centerX, y: centerY))
                        AppCoordinator.shared.mainWindow = window
                        appVM.mainWindow = window
                    }

                    // Create the single status bar item (AppKit)
                    let bar = StatusBarController()
                    bar.setup(vm: appVM)
                    self.statusBar = bar
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
