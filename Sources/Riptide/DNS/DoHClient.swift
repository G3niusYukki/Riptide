import Foundation

public final class DoHClient: Sendable {
    private let serverURL: URL
    private let timeout: Duration

    public init(serverURL: URL = URL(string: "https://dns.google/dns-query")!, timeout: Duration = .seconds(5)) {
        self.serverURL = serverURL
        self.timeout = timeout
    }

    public func query(name: String, type: DNSRecordType = .a, id: UInt16 = 0) async throws -> DNSMessage {
        let queryMsg = DNSMessage.buildQuery(name: name, type: type, id: id)
        let requestData = try queryMsg.encode()

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = requestData
        request.timeoutInterval = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DNSError.serverError("invalid HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            throw DNSError.serverError("DoH server returned HTTP \(httpResponse.statusCode)")
        }

        return try DNSMessage.parse(responseData)
    }
}
