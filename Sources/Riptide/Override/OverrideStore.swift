import Foundation

public enum OverrideStoreError: Error, Equatable, Sendable {
    case notFound(UUID)
    case persistenceFailed(String)
}

public actor OverrideStore {
    private var overrides: [UUID: Override] = [:]
    private let directoryURL: URL
    private let sidecarURL: URL

    public init(
        directoryName: String = "overrides",
        fileName: String = "overrides.json"
    ) throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OverrideStoreError.persistenceFailed("Application Support directory unavailable")
        }
        let baseDir = appSupport.appendingPathComponent("Riptide", isDirectory: true)
        self.directoryURL = baseDir.appendingPathComponent(directoryName, isDirectory: true)
        self.sidecarURL = directoryURL.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let loaded = try Self.loadFromDisk(sidecarURL: sidecarURL)
        self.overrides = loaded
    }

    // MARK: - Public API

    public func list() throws -> [Override] {
        Array(overrides.values).sorted { $0.name < $1.name }
    }

    public func get(id: UUID) throws -> Override {
        guard let o = overrides[id] else { throw OverrideStoreError.notFound(id) }
        return o
    }

    public func create(name: String, rawYAML: String) throws -> Override {
        let now = Date()
        let ovr = Override(
            name: name,
            rawYAML: rawYAML,
            createdAt: now,
            updatedAt: now
        )
        overrides[ovr.id] = ovr
        try writeYAMLFile(for: ovr)
        try saveSidecar()
        return ovr
    }

    public func update(id: UUID, name: String?, rawYAML: String?) throws -> Override {
        guard var existing = overrides[id] else { throw OverrideStoreError.notFound(id) }
        if let name { existing.name = name }
        if let rawYAML {
            existing.rawYAML = rawYAML
            try writeYAMLFile(for: existing)
        }
        existing.updatedAt = Date()
        overrides[id] = existing
        try saveSidecar()
        return existing
    }

    public func delete(id: UUID) throws {
        guard let existing = overrides[id] else { throw OverrideStoreError.notFound(id) }
        let yamlFile = directoryURL.appendingPathComponent("\(existing.id.uuidString).yaml")
        try? FileManager.default.removeItem(at: yamlFile)
        overrides.removeValue(forKey: id)
        try saveSidecar()
    }

    // MARK: - Persistence

    private func writeYAMLFile(for ovr: Override) throws {
        let url = directoryURL.appendingPathComponent("\(ovr.id.uuidString).yaml")
        do {
            try ovr.rawYAML.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw OverrideStoreError.persistenceFailed("write yaml: \(error.localizedDescription)")
        }
    }

    private func saveSidecar() throws {
        let arr = Array(overrides.values)
        do {
            let data = try JSONEncoder().encode(arr)
            try data.write(to: sidecarURL, options: .atomic)
        } catch {
            throw OverrideStoreError.persistenceFailed("write sidecar: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk(sidecarURL: URL) throws -> [UUID: Override] {
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: sidecarURL)
            let arr = try JSONDecoder().decode([Override].self, from: data)
            return Dictionary(uniqueKeysWithValues: arr.map { ($0.id, $0) })
        } catch {
            throw OverrideStoreError.persistenceFailed("load sidecar: \(error.localizedDescription)")
        }
    }
}
