import SwiftUI
import Riptide

@MainActor
@Observable
final class ProxyViewModel {
    var proxyNodes: [ProxyNode] = []
    var selectedProxy: String = ""

    func loadProxies(_ proxies: [ProxyNode]) {
        self.proxyNodes = proxies
        if selectedProxy.isEmpty, let first = proxies.first {
            selectedProxy = first.name
        }
    }
}
