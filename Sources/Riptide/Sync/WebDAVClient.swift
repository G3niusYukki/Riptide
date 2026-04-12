import Foundation

// MARK: - WebDAV Client

/// Low-level WebDAV client using URLSession
public actor WebDAVClient {
    private let serverURL: URL
    private let username: String
    private let password: String
    private let urlSession: URLSession
    private let decoder = XMLDecoder()

    public init(serverURL: URL, username: String, password: String) {
        self.serverURL = serverURL
        self.username = username
        self.password = password

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - URL Resolution

    /// Build a URL by normalizing the path and resolving it against the server URL.
    private func resolvedURL(for path: String) -> URL? {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalizedPath.isEmpty {
            return serverURL
        }

        var baseURL = serverURL
        if !baseURL.absoluteString.hasSuffix("/") {
            baseURL = baseURL.appendingPathComponent("")
        }

        return URL(string: normalizedPath, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - WebDAV Operations

    /// List files in a directory using PROPFIND
    public func listFiles(path: String) async throws -> [WebDAVFile] {
        guard let url = resolvedURL(for: path),
              url.scheme?.hasPrefix("http") == true else {
            throw WebDAVError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(createAuthHeader(), forHTTPHeaderField: "Authorization")

        let propfindBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:displayname/>
                <D:getcontentlength/>
                <D:getlastmodified/>
                <D:resourcetype/>
                <D:getetag/>
            </D:prop>
        </D:propfind>
        """

        request.httpBody = propfindBody.data(using: .utf8)

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.networkError("Invalid response type")
            }

            switch httpResponse.statusCode {
            case 200...299:
                return try parsePropfindResponse(data, basePath: path)
            case 401:
                throw WebDAVError.invalidCredentials
            case 404:
                throw WebDAVError.notFound
            default:
                throw WebDAVError.serverError(
                    httpResponse.statusCode,
                    String(data: data, encoding: .utf8) ?? "Unknown error"
                )
            }
        } catch let error as WebDAVError {
            throw error
        } catch {
            throw WebDAVError.listFailed(String(describing: error))
        }
    }

    /// Download a file using GET
    public func download(path: String) async throws -> Data {
        guard let url = resolvedURL(for: path),
              url.scheme?.hasPrefix("http") == true else {
            throw WebDAVError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(createAuthHeader(), forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.networkError("Invalid response type")
            }

            switch httpResponse.statusCode {
            case 200...299:
                return data
            case 401:
                throw WebDAVError.invalidCredentials
            case 404:
                throw WebDAVError.notFound
            default:
                throw WebDAVError.serverError(
                    httpResponse.statusCode,
                    String(data: data, encoding: .utf8) ?? "Unknown error"
                )
            }
        } catch let error as WebDAVError {
            throw error
        } catch {
            throw WebDAVError.downloadFailed(String(describing: error))
        }
    }

    /// Upload a file using PUT
    public func upload(path: String, data: Data, contentType: String = "application/json") async throws {
        guard let url = resolvedURL(for: path),
              url.scheme?.hasPrefix("http") == true else {
            throw WebDAVError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(createAuthHeader(), forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        do {
            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.networkError("Invalid response type")
            }

            switch httpResponse.statusCode {
            case 200...299, 201:
                return
            case 401:
                throw WebDAVError.invalidCredentials
            case 403:
                throw WebDAVError.uploadFailed("Permission denied")
            case 507:
                throw WebDAVError.uploadFailed("Insufficient storage")
            default:
                throw WebDAVError.serverError(
                    httpResponse.statusCode,
                    "Upload failed"
                )
            }
        } catch let error as WebDAVError {
            throw error
        } catch {
            throw WebDAVError.uploadFailed(String(describing: error))
        }
    }

    /// Delete a file using DELETE
    public func delete(path: String) async throws {
        guard let url = resolvedURL(for: path),
              url.scheme?.hasPrefix("http") == true else {
            throw WebDAVError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(createAuthHeader(), forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.networkError("Invalid response type")
            }

            switch httpResponse.statusCode {
            case 200...299, 204:
                return
            case 401:
                throw WebDAVError.invalidCredentials
            case 404:
                return
            default:
                throw WebDAVError.serverError(
                    httpResponse.statusCode,
                    "Delete failed"
                )
            }
        } catch let error as WebDAVError {
            throw error
        } catch {
            throw WebDAVError.deleteFailed(String(describing: error))
        }
    }

    /// Create a directory using MKCOL
    public func createDirectory(path: String) async throws {
        guard let url = resolvedURL(for: path),
              url.scheme?.hasPrefix("http") == true else {
            throw WebDAVError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        request.setValue(createAuthHeader(), forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.networkError("Invalid response type")
            }

            switch httpResponse.statusCode {
            case 200...299, 201:
                return
            case 401:
                throw WebDAVError.invalidCredentials
            case 405:
                return
            case 409:
                throw WebDAVError.uploadFailed("Parent directory does not exist")
            default:
                throw WebDAVError.serverError(
                    httpResponse.statusCode,
                    "MKCOL failed"
                )
            }
        } catch let error as WebDAVError {
            throw error
        } catch {
            throw WebDAVError.uploadFailed(String(describing: error))
        }
    }

    /// Test the connection by listing the root directory
    public func testConnection() async throws {
        _ = try await listFiles(path: "/")
    }

    // MARK: - Private Methods

    private func createAuthHeader() -> String {
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else { return "" }
        return "Basic \(data.base64EncodedString())"
    }

    private func parsePropfindResponse(_ data: Data, basePath: String) throws -> [WebDAVFile] {
        var files: [WebDAVFile] = []

        let parser = XMLParser(data: data)
        let delegate = PropfindParserDelegate(basePath: basePath)
        parser.delegate = delegate

        if parser.parse() {
            files = delegate.files
        } else if let error = parser.parserError {
            throw WebDAVError.parsingError(String(describing: error))
        }

        return files
    }
}

// MARK: - XML Parser Delegate

private final class PropfindParserDelegate: NSObject, XMLParserDelegate {
    var files: [WebDAVFile] = []
    private var basePath: String

    private var currentElement = ""
    private var currentHref = ""
    private var currentName = ""
    private var currentSize = 0
    private var currentModified = Date()
    private var currentIsDirectory = false
    private var currentEtag: String?

    // Accumulate raw character data per element (XMLParser may call foundCharacters multiple times)
    private var elementBuffer = ""

    private var inResponse = false
    private var inPropstat = false
    private var inProp = false

    init(basePath: String) {
        self.basePath = basePath
        super.init()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        if elementName == "D:response" || elementName == "response" {
            inResponse = true
            currentHref = ""
            currentName = ""
            currentSize = 0
            currentIsDirectory = false
            currentEtag = nil
            elementBuffer = ""
        } else if elementName == "D:propstat" || elementName == "propstat" {
            inPropstat = true
        } else if elementName == "D:prop" || elementName == "prop" {
            inProp = true
        } else if (elementName == "D:collection" || elementName == "collection") && inProp {
            currentIsDirectory = true
        }
        elementBuffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        elementBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = elementBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        // Process accumulated character data based on the closing element
        if !trimmed.isEmpty {
            if elementName == "D:href" || elementName == "href" {
                currentHref += trimmed
            } else if elementName == "D:displayname" || elementName == "displayname" {
                currentName += trimmed
            } else if elementName == "D:getcontentlength" || elementName == "getcontentlength" {
                currentSize = Int(trimmed) ?? 0
            } else if elementName == "D:getlastmodified" || elementName == "getlastmodified" {
                if let date = parseDAVDate(trimmed) {
                    currentModified = date
                }
            } else if elementName == "D:getetag" || elementName == "getetag" {
                currentEtag = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        if elementName == "D:response" || elementName == "response" {
            inResponse = false

            let name = currentName.isEmpty ? (currentHref as NSString).lastPathComponent : currentName
            let path = currentHref.hasPrefix("/") ? currentHref : basePath + "/" + currentHref

            let file = WebDAVFile(
                path: path,
                name: name,
                size: currentSize,
                modified: currentModified,
                isDirectory: currentIsDirectory,
                etag: currentEtag
            )

            files.append(file)
        } else if elementName == "D:propstat" || elementName == "propstat" {
            inPropstat = false
        } else if elementName == "D:prop" || elementName == "prop" {
            inProp = false
        }

        currentElement = ""
    }

    private func parseDAVDate(_ string: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: string)
    }
}

// MARK: - XML Decoder Placeholder

private struct XMLDecoder {
    // Placeholder for XML decoding if needed
}
