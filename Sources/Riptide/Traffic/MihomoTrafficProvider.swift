import Foundation

// MARK: - Mihomo Traffic Provider

/// Traffic provider that fetches from mihomo API
public actor MihomoTrafficProvider: TrafficProvider {
    private let apiClient: MihomoAPIClient

    public init(apiClient: MihomoAPIClient) {
        self.apiClient = apiClient
    }

    public func getTraffic() async throws -> (up: Int, down: Int) {
        try await apiClient.getTraffic()
    }
}
