import Foundation

/// A minimal MaxMind MMDB (.mmdb) parser for country-code lookups.
///
/// Supports IPv4 lookups. The MMDB format uses a binary tree where each node
/// points to either another node or a data record containing the country code.
public final class GeoIPDatabase: Sendable {

    // MARK: - Errors

    public enum GeoIPError: Error, Equatable, Sendable {
        case invalidFile(String)
        case corruptMetadata(String)
        case lookupFailed(String)
        case unsupportedVersion(String)

        public var localizedDescription: String {
            switch self {
            case .invalidFile(let msg): return "Invalid MMDB file: \(msg)"
            case .corruptMetadata(let msg): return "Corrupt MMDB metadata: \(msg)"
            case .lookupFailed(let msg): return "GeoIP lookup failed: \(msg)"
            case .unsupportedVersion(let msg): return "Unsupported MMDB version: \(msg)"
            }
        }
    }

    // MARK: - Metadata

    private struct Metadata: Sendable {
        let nodeCount: Int
        let recordSize: Int
        let ipVersion: Int
        let databaseType: String

        init(nodeCount: Int, recordSize: Int, ipVersion: Int, databaseType: String) {
            self.nodeCount = nodeCount
            self.recordSize = recordSize
            self.ipVersion = ipVersion
            self.databaseType = databaseType
        }
    }

    // MARK: - State

    private let data: Data
    private let metadata: Metadata
    private let dataSectionStartOffset: Int

    // MARK: - Init

    public init(filePath: String) throws {
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw GeoIPError.invalidFile("file does not exist: \(filePath)")
        }

        self.data = try Data(contentsOf: fileURL)
        guard data.count > 128 else {
            throw GeoIPError.invalidFile("file too small")
        }

        self.metadata = try Self.parseMetadata(from: data)

        guard metadata.ipVersion == 4 || metadata.ipVersion == 6 else {
            throw GeoIPError.unsupportedVersion("IP version \(metadata.ipVersion)")
        }
        guard metadata.recordSize == 24 || metadata.recordSize == 28 || metadata.recordSize == 32 else {
            throw GeoIPError.corruptMetadata("unsupported record size: \(metadata.recordSize)")
        }

        let nodeByteSize = metadata.recordSize / 8
        let treeSize = metadata.nodeCount * nodeByteSize * 2
        self.dataSectionStartOffset = treeSize + 16  // 16-byte separator
    }

    // MARK: - Public

    public func lookupCountryCode(forIP ipAddress: String) -> String? {
        guard let ipValue = IPv4AddressParser.parse(ipAddress) else { return nil }

        let recordBytes = ipToSearchBytes(ipValue)
        var nodeIndex = 0

        for bitIndex in 0..<32 {
            let bit = (recordBytes[bitIndex / 8] >> (7 - (bitIndex % 8))) & 1
            let nodeOffset = nodeIndex * (metadata.recordSize / 8) * 2

            let childIndex: Int
            if bit == 0 {
                childIndex = readNodeIndex(at: nodeOffset)
            } else {
                childIndex = readNodeIndex(at: nodeOffset + metadata.recordSize / 8)
            }

            if childIndex == metadata.nodeCount {
                return nil
            } else if childIndex > metadata.nodeCount {
                return readCountryCode(from: childIndex)
            } else {
                nodeIndex = childIndex
            }
        }

        return nil
    }

    public var nodeCount: Int { metadata.nodeCount }
    public var databaseType: String { metadata.databaseType }

    // MARK: - Private — Tree Reading

    private func readNodeIndex(at offset: Int) -> Int {
        guard offset + (metadata.recordSize / 8) <= data.count else {
            return metadata.nodeCount
        }

        switch metadata.recordSize {
        case 24:
            return Int(data[offset]) << 16 | Int(data[offset + 1]) << 8 | Int(data[offset + 2])
        case 28:
            let base = Int(data[offset]) << 16 | Int(data[offset + 1]) << 8 | Int(data[offset + 2])
            let extra = Int(data[offset + 3] >> 4)
            return (extra << 24) | base
        case 32:
            return Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 |
                   Int(data[offset + 2]) << 8 | Int(data[offset + 3])
        default:
            return metadata.nodeCount
        }
    }

    private func readCountryCode(from pointer: Int) -> String? {
        let offset = dataSectionStartOffset + (pointer - metadata.nodeCount)
        guard offset < data.count else { return nil }

        let byte = data[offset]
        let dataType = byte >> 5
        let sizeValue = Int(byte & 0x1F)

        guard dataType == 0x02 else { return nil }  // utf8_string

        let length: Int
        let dataOffset: Int

        if sizeValue < 29 {
            length = sizeValue
            dataOffset = offset + 1
        } else if sizeValue == 29 {
            length = 29 + Int(data[offset + 1])
            dataOffset = offset + 2
        } else if sizeValue == 30 {
            length = 285 + (Int(data[offset + 1]) << 8) | Int(data[offset + 2])
            dataOffset = offset + 3
        } else {
            return nil
        }

        guard dataOffset + length <= data.count else { return nil }
        return String(data: data.subdata(in: dataOffset..<dataOffset + length), encoding: .utf8)
    }

    // MARK: - Private — Metadata Parsing

    private static func parseMetadata(from data: Data) throws -> Metadata {
        let magic: [UInt8] = [0xAB, 0xCD, 0xEF, 0x4D, 0x61, 0x78, 0x4D, 0x69, 0x6E, 0x64, 0x2E, 0x63, 0x6F, 0x6D]

        var metadataStart = -1
        for i in stride(from: data.count - magic.count, through: 0, by: -1) {
            var found = true
            for j in 0..<magic.count {
                if data[i + j] != magic[j] {
                    found = false
                    break
                }
            }
            if found {
                metadataStart = i
                break
            }
        }

        guard metadataStart >= 0 else {
            throw GeoIPError.invalidFile("magic bytes not found")
        }

        let metadataSection = data.subdata(in: metadataStart..<data.count)

        let nodeCount = try parseIntField(from: metadataSection, key: "node_count")
        let recordSize = try parseIntField(from: metadataSection, key: "record_size")
        let ipVersion = try parseIntField(from: metadataSection, key: "ip_version")
        let databaseType = try parseStringField(from: metadataSection, key: "database_type")

        return Metadata(
            nodeCount: nodeCount,
            recordSize: recordSize,
            ipVersion: ipVersion,
            databaseType: databaseType
        )
    }

    private static func parseIntField(from data: Data, key: String) throws -> Int {
        guard let keyData = key.data(using: .ascii) else {
            throw GeoIPError.corruptMetadata("invalid key: \(key)")
        }

        for i in 0..<(data.count - keyData.count) {
            if data.subdata(in: i..<i + keyData.count) == keyData {
                let valueOffset = i + keyData.count
                guard valueOffset < data.count else { continue }

                let valueByte = data[valueOffset]
                let valueType = valueByte >> 5
                let valueSize = Int(valueByte & 0x1F)

                guard valueType == 0x01 else { continue }  // uint32

                let dataStart = valueOffset + 1
                guard dataStart + valueSize <= data.count else { continue }

                var value: Int = 0
                for j in 0..<valueSize {
                    value = (value << 8) | Int(data[dataStart + j])
                }
                return value
            }
        }

        throw GeoIPError.corruptMetadata("key not found: \(key)")
    }

    private static func parseStringField(from data: Data, key: String) throws -> String {
        guard let keyData = key.data(using: .ascii) else {
            throw GeoIPError.corruptMetadata("invalid key: \(key)")
        }

        for i in 0..<(data.count - keyData.count) {
            if data.subdata(in: i..<i + keyData.count) == keyData {
                let valueOffset = i + keyData.count
                guard valueOffset < data.count else { continue }

                let valueByte = data[valueOffset]
                let valueType = valueByte >> 5
                let valueSize = Int(valueByte & 0x1F)

                guard valueType == 0x02 else { continue }  // utf8_string

                let dataStart = valueOffset + 1
                guard dataStart + valueSize <= data.count else { continue }

                if let string = String(data: data.subdata(in: dataStart..<dataStart + valueSize), encoding: .utf8) {
                    return string
                }
            }
        }

        throw GeoIPError.corruptMetadata("string key not found: \(key)")
    }

    // MARK: - Private — IP Conversion

    private func ipToSearchBytes(_ ip: UInt32) -> [UInt8] {
        [
            UInt8((ip >> 24) & 0xFF),
            UInt8((ip >> 16) & 0xFF),
            UInt8((ip >> 8) & 0xFF),
            UInt8(ip & 0xFF)
        ]
    }
}
