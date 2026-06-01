import SwiftUI
import AppKit
import Riptide
import Sparkle

// Shared coordinator — holds the main window reference for the entire app
@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()
    var mainWindow: NSWindow?

    /// Sparkle updater controller — initialized once, shared across the app.
    lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()

    private init() {}
}

@main
struct RiptideApp: App {
    @State private var appVM = AppViewModel()
    @State private var statusBar: StatusBarController?
    @StateObject private var themeManager = ThemeManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some SwiftUI.Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView(vm: appVM, themeManager: themeManager)
                    .accessibilityIdentifier("app.main-window")
                    .preferredColorScheme(colorScheme)
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
            } else {
                OnboardingView(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { newValue in hasCompletedOnboarding = !newValue }
                ))
            }
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    AppCoordinator.shared.updaterController.checkForUpdates(nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch themeManager.appearanceMode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
