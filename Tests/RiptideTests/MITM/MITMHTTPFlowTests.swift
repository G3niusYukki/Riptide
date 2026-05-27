import Foundation
import Testing
@testable import Riptide

@Suite("MITM HTTP flow")
struct MITMHTTPFlowTests {
    @Test("parser emits complete request after headers and content length body arrive")
    func parserEmitsCompleteRequest() {
        var parser = MITMHTTPMessageParser(direction: .request, bodyPreviewLimit: 16)

        let firstChunk = Data("POST /submit HTTP/1.1\r\nHost: example.com\r\nContent-Length: 5\r\n\r\nhe".utf8)
        #expect(parser.append(firstChunk).isEmpty)

        let messages = parser.append(Data("llo".utf8))

        #expect(messages.count == 1)
        guard case .request(let request) = messages.first else {
            Issue.record("Expected a request message")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/submit")
        #expect(request.version == "HTTP/1.1")
        #expect(request.headerValue("host") == "example.com")
        #expect(request.bodySize == 5)
        #expect(request.bodyPreviewText == "hello")
    }

    @Test("parser emits complete response with status and body preview")
    func parserEmitsCompleteResponse() {
        var parser = MITMHTTPMessageParser(direction: .response, bodyPreviewLimit: 16)

        let messages = parser.append(
            Data("HTTP/1.1 201 Created\r\nContent-Length: 7\r\n\r\ncreated".utf8)
        )

        #expect(messages.count == 1)
        guard case .response(let response) = messages.first else {
            Issue.record("Expected a response message")
            return
        }
        #expect(response.version == "HTTP/1.1")
        #expect(response.statusCode == 201)
        #expect(response.reasonPhrase == "Created")
        #expect(response.bodySize == 7)
        #expect(response.bodyPreviewText == "created")
    }

    @Test("manager stores request and later attaches response")
    func managerStoresRequestAndAttachesResponse() async {
        let manager = MITMManager()
        let request = MITMHTTPRequest(
            method: "GET",
            path: "/",
            version: "HTTP/1.1",
            headers: [MITMHTTPHeader(name: "Host", value: "example.com")],
            bodySize: 0,
            bodyPreview: Data()
        )
        let response = MITMHTTPResponse(
            version: "HTTP/1.1",
            statusCode: 200,
            reasonPhrase: "OK",
            headers: [MITMHTTPHeader(name: "Content-Length", value: "2")],
            bodySize: 2,
            bodyPreview: Data("OK".utf8)
        )

        let id = await manager.recordHTTPRequest(host: "example.com", port: 443, request: request)
        await manager.recordHTTPResponse(flowID: id, response: response)

        let records = await manager.recentHTTPFlowRecords()

        #expect(records.count == 1)
        #expect(records[0].id == id)
        #expect(records[0].host == "example.com")
        #expect(records[0].request.method == "GET")
        #expect(records[0].response?.statusCode == 200)
        #expect(records[0].response?.bodyPreviewText == "OK")
    }
}
