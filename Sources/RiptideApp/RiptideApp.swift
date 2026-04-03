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
    @State private var vpnVM = VPNViewModel()
    @State private var proxyVM = ProxyViewModel()
    @State private var menuBarVM: MenuBarViewModel?
    @State private var selectedTab = 0

    var body: some SwiftUI.Scene {
        MenuBarExtra {
            if let menuBarVM {
                RiptideMenuBar(viewModel: menuBarVM)
            }
        } label: {
            Image(systemName: vpnVM.isRunning ? "shield.checkmark.fill" : "shield.slash")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup {
            MainTabView(vm: appVM)
                .preferredColorScheme(.dark)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    // Guard against multiple onAppear calls creating duplicate StatusBarControllers.
                    if self.statusBar == nil {
                        if let window = NSApp.windows.first {
                            if let screen = NSScreen.main ?? NSScreen.screens.first {
                                let screenFrame = screen.visibleFrame
                                let windowSize = window.frame.size
                                let centerX = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
                                let centerY = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
                                window.setFrameOrigin(NSPoint(x: centerX, y: centerY))
                            }
                            AppCoordinator.shared.mainWindow = window
                            appVM.mainWindow = window
                        }
                        let bar = StatusBarController()
                        bar.setup(vm: appVM)
                        self.statusBar = bar
                    }
                }
            .frame(minWidth: 700, minHeight: 450)
            .task {
                menuBarVM = MenuBarViewModel(appViewModel: appVM)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)
    }
}
