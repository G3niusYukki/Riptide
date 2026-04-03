import Foundation

public actor MITMManager {
    private let ca: CertificateAuthority
    private var enabled: Bool = false

    public init(ca: CertificateAuthority = CertificateAuthority()) {
        self.ca = ca
    }

    public func enable() async {
        enabled = true
    }

    public func disable() {
        enabled = false
    }

    public var isEnabled: Bool { enabled }

    public func shouldIntercept(_ host: String) -> Bool {
        guard enabled else { return false }
        return true
    }
}
