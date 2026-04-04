import Foundation

/// Actor that monitors and guards system proxy settings
public actor SystemProxyGuard {
    private let controller: any SystemProxyControlling
    private var isGuardEnabled: Bool = false
    private var expectedHTTPPort: Int?
    private var expectedSOCKSPort: Int?
    private var violationCount: Int = 0

    public init(controller: any SystemProxyControlling) {
        self.controller = controller
    }

    /// Enables the guard with expected proxy settings
    public func enable(expectedHTTPPort: Int, expectedSOCKSPort: Int?) throws {
        self.expectedHTTPPort = expectedHTTPPort
        self.expectedSOCKSPort = expectedSOCKSPort
        self.isGuardEnabled = true
        self.violationCount = 0

        // Immediately set the proxy to expected values
        try controller.enable(httpPort: expectedHTTPPort, socksPort: expectedSOCKSPort)
    }

    /// Disables the guard
    public func disable() {
        isGuardEnabled = false
    }

    /// Returns whether the guard is currently enabled
    public func isEnabled() -> Bool {
        isGuardEnabled
    }

    /// Checks if current proxy settings match expected values
    public func checkForViolation() -> Bool {
        guard isGuardEnabled else { return false }

        do {
            let currentState = try controller.currentState()

            switch currentState {
            case .disabled:
                // Proxy is disabled when it should be enabled
                violationCount += 1
                return true

            case .enabled(let httpPort, let socksPort):
                // Check if ports match expected values
                if let expectedHTTP = expectedHTTPPort, httpPort != expectedHTTP {
                    violationCount += 1
                    return true
                }
                if let expectedSOCKS = expectedSOCKSPort, socksPort != expectedSOCKS {
                    violationCount += 1
                    return true
                }
                return false
            }
        } catch {
            // Error checking state counts as violation
            violationCount += 1
            return true
        }
    }

    /// Restores proxy settings to expected values
    public func restore() throws {
        guard isGuardEnabled,
              let httpPort = expectedHTTPPort else {
            return
        }

        try controller.enable(httpPort: httpPort, socksPort: expectedSOCKSPort)
    }

    /// Returns the number of detected violations
    public func getViolationCount() -> Int {
        violationCount
    }

    /// Gets the expected proxy settings
    public func getExpectedSettings() -> (httpPort: Int?, socksPort: Int?) {
        (expectedHTTPPort, expectedSOCKSPort)
    }
}
