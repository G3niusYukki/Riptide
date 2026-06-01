import SwiftUI
import WidgetKit

/// The top-level widget bundle for the Riptide widget extension.
///
/// When this library is later wrapped in a `.appex` extension target, the
/// extension's main file should add an `@main` wrapper around an instance
/// of this bundle (see INSTALLATION.md). We deliberately do not mark this
/// type `@main` here — that would synthesize a `main()` symbol in the
/// library and conflict with the test runner's own entry point.
public struct RiptideWidgetBundle: WidgetBundle {
    public init() {}

    public var body: some Widget {
        RiptideSpeedWidget()
    }
}
