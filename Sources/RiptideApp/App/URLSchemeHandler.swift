import Foundation

/// Routes `riptide://` URL scheme commands to the app's view model.
///
/// The five supported URL forms are:
/// - `riptide://switch?group=NAME` (also `?name=NAME`) — switch to proxy group `NAME`
/// - `riptide://select?node=NAME` — select node `NAME` in the matching group
/// - `riptide://mode?value=tun|system|off` — switch the proxy mode
/// - `riptide://import?url=URL` — pre-fill the subscription import dialog with `URL`
/// - `riptide://diagnostics` — generate a diagnostic report
///
/// The handler is split into a pure parser (`parse`) and a side-effecting
/// router (`route`) so the parser can be unit-tested without a running app.
public enum URLSchemeHandler {

    /// Parsed action extracted from a `riptide://` URL.
    public enum Action: Sendable, Equatable {
        case switchGroup(name: String)
        case selectNode(name: String)
        case setMode(value: String)
        case importSubscription(url: String)
        case runDiagnostics
    }

    /// The URL scheme handled by this app. Exposed for tests and registration.
    public static let scheme = "riptide"

    /// Parse a URL into an `Action`. Returns `nil` for any URL that is not a
    /// recognized `riptide://` command — the caller is expected to log and
    /// continue rather than crash.
    public static func parse(_ url: URL) -> Action? {
        guard url.scheme == scheme else { return nil }
        let host = url.host ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let value = queryItems.first(where: { $0.name == "value" })?.value ?? ""
        // `group` is the spec's canonical name; `name` is accepted as an alias.
        let groupName = queryItems.first(where: { $0.name == "group" || $0.name == "name" })?.value ?? ""
        let nodeName = queryItems.first(where: { $0.name == "node" })?.value ?? ""
        let importURL = queryItems.first(where: { $0.name == "url" })?.value ?? ""

        switch host {
        case "switch":
            return groupName.isEmpty ? nil : .switchGroup(name: groupName)
        case "select":
            return nodeName.isEmpty ? nil : .selectNode(name: nodeName)
        case "mode":
            return .setMode(value: value)
        case "import":
            return .importSubscription(url: importURL)
        case "diagnostics":
            return .runDiagnostics
        default:
            return nil
        }
    }

    /// Route a URL to the view model. Returns `true` if the URL was recognized
    /// and dispatched; `false` otherwise (the caller may log the bad URL).
    @MainActor
    @discardableResult
    public static func route(_ url: URL, viewModel: AppViewModel) async -> Bool {
        guard let action = parse(url) else {
            viewModel.urlSchemeError = "Unrecognized URL: \(url.absoluteString)"
            return false
        }
        switch action {
        case .switchGroup(let name):
            await viewModel.selectGroup(named: name)
        case .selectNode(let name):
            await viewModel.selectNode(named: name)
        case .setMode(let value):
            await viewModel.setMode(fromString: value)
        case .importSubscription(let urlString):
            viewModel.pendingImportURL = urlString
        case .runDiagnostics:
            await viewModel.runDiagnostics()
        }
        return true
    }
}
