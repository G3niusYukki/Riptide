import Foundation

public enum DNSRecordType: UInt16, Sendable, Equatable {
    case a = 1
    case ns = 2
    case cname = 5
    case soa = 6
    case ptr = 12
    case mx = 15
    case txt = 16
    case aaaa = 28
    case srv = 33
    case https = 65

    public static func from(_ value: UInt16) -> DNSRecordType? {
        DNSRecordType(rawValue: value)
    }
}

public enum DNSClass: UInt16, Sendable, Equatable {
    case inet = 1
    case inet6 = 28
}

public enum DNSResponseCode: UInt8, Sendable, Equatable {
    case noError = 0
    case formError = 1
    case serverFailure = 2
    case nameError = 3
    case notImplemented = 4
    case refused = 5
}

public struct DNSHeader: Sendable {
    public let id: UInt16
    public let isResponse: Bool
    public let opcode: UInt8
    public let authoritative: Bool
    public let truncated: Bool
    public let recursionDesired: Bool
    public let recursionAvailable: Bool
    public let responseCode: DNSResponseCode
    public let questionCount: UInt16
    public let answerCount: UInt16
    public let authorityCount: UInt16
    public let additionalCount: UInt16

    public init(
        id: UInt16 = 0,
        isResponse: Bool = false,
        opcode: UInt8 = 0,
        authoritative: Bool = false,
        truncated: Bool = false,
        recursionDesired: Bool = true,
        recursionAvailable: Bool = false,
        responseCode: DNSResponseCode = .noError,
        questionCount: UInt16 = 0,
        answerCount: UInt16 = 0,
        authorityCount: UInt16 = 0,
        additionalCount: UInt16 = 0
    ) {
        self.id = id
        self.isResponse = isResponse
        self.opcode = opcode
        self.authoritative = authoritative
        self.truncated = truncated
        self.recursionDesired = recursionDesired
        self.recursionAvailable = recursionAvailable
        self.responseCode = responseCode
        self.questionCount = questionCount
        self.answerCount = answerCount
        self.authorityCount = authorityCount
        self.additionalCount = additionalCount
    }

    func encode() -> Data {
        var data = Data(count: 12)
        data[0] = UInt8(id >> 8)
        data[1] = UInt8(id & 0xFF)
        var flags: UInt16 = 0
        if isResponse { flags |= 0x8000 }
        flags |= UInt16(opcode) << 11
        if authoritative { flags |= 0x0400 }
        if truncated { flags |= 0x0200 }
        if recursionDesired { flags |= 0x0100 }
        if recursionAvailable { flags |= 0x0080 }
        flags |= UInt16(responseCode.rawValue)
        data[2] = UInt8(flags >> 8)
        data[3] = UInt8(flags & 0xFF)
        data[4] = UInt8(questionCount >> 8)
        data[5] = UInt8(questionCount & 0xFF)
        data[6] = UInt8(answerCount >> 8)
        data[7] = UInt8(answerCount & 0xFF)
        data[8] = UInt8(authorityCount >> 8)
        data[9] = UInt8(authorityCount & 0xFF)
        data[10] = UInt8(additionalCount >> 8)
        data[11] = UInt8(additionalCount & 0xFF)
        return data
    }

    static func parse(_ data: Data, offset: Int = 0) throws -> (header: DNSHeader, consumed: Int) {
        guard data.count >= offset + 12 else {
            throw DNSError.malformedMessage("header too short")
        }
        let id = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        let flags = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
        let isResponse = (flags & 0x8000) != 0
        let opcode = UInt8((flags >> 11) & 0x0F)
        let authoritative = (flags & 0x0400) != 0
        let truncated = (flags & 0x0200) != 0
        let recursionDesired = (flags & 0x0100) != 0
        let recursionAvailable = (flags & 0x0080) != 0
        let rcode = DNSResponseCode(rawValue: UInt8(flags & 0x000F)) ?? .noError
        let qdcount = UInt16(data[offset + 4]) << 8 | UInt16(data[offset + 5])
        let ancount = UInt16(data[offset + 6]) << 8 | UInt16(data[offset + 7])
        let nscount = UInt16(data[offset + 8]) << 8 | UInt16(data[offset + 9])
        let arcount = UInt16(data[offset + 10]) << 8 | UInt16(data[offset + 11])

        let header = DNSHeader(
            id: id, isResponse: isResponse, opcode: opcode,
            authoritative: authoritative, truncated: truncated,
            recursionDesired: recursionDesired,
            recursionAvailable: recursionAvailable,
            responseCode: rcode,
            questionCount: qdcount, answerCount: ancount,
            authorityCount: nscount, additionalCount: arcount
        )
        return (header, 12)
    }
}

public struct DNSQuestion: Sendable {
    public let name: String
    public let type: DNSRecordType
    public let classValue: DNSClass

    public init(name: String, type: DNSRecordType, classValue: DNSClass = .inet) {
        self.name = name
        self.type = type
        self.classValue = classValue
    }
}

public struct DNSResourceRecord: Sendable {
    public let name: String
    public let type: DNSRecordType
    public let classValue: DNSClass
    public let ttl: UInt32
    public let rdata: Data

    public var addressString: String? {
        switch type {
        case .a where rdata.count == 4:
            return "\(rdata[0]).\(rdata[1]).\(rdata[2]).\(rdata[3])"
        case .aaaa where rdata.count == 16:
            var parts: [String] = []
            for i in stride(from: 0, to: 16, by: 2) {
                let val = UInt16(rdata[i]) << 8 | UInt16(rdata[i + 1])
                parts.append(String(format: "%x", val))
            }
            return parts.joined(separator: ":")
        default:
            return nil
        }
    }
}

public struct DNSMessage: Sendable {
    public let header: DNSHeader
    public let questions: [DNSQuestion]
    public let answers: [DNSResourceRecord]
    public let authorities: [DNSResourceRecord]
    public let additionals: [DNSResourceRecord]

    public init(header: DNSHeader, questions: [DNSQuestion] = [], answers: [DNSResourceRecord] = [],
                authorities: [DNSResourceRecord] = [], additionals: [DNSResourceRecord] = []) {
        self.header = header
        self.questions = questions
        self.answers = answers
        self.authorities = authorities
        self.additionals = additionals
    }

    public static func buildQuery(name: String, type: DNSRecordType, id: UInt16 = 0) -> DNSMessage {
        DNSMessage(
            header: DNSHeader(id: id, questionCount: 1),
            questions: [DNSQuestion(name: name, type: type)]
        )
    }

    public func encode() throws -> Data {
        var data = header.encode()
        for q in questions {
            data.append(try encodeDomainName(q.name))
            data.append(UInt8(q.type.rawValue >> 8))
            data.append(UInt8(q.type.rawValue & 0xFF))
            data.append(UInt8(q.classValue.rawValue >> 8))
            data.append(UInt8(q.classValue.rawValue & 0xFF))
        }
        for rr in answers + authorities + additionals {
            data.append(try encodeDomainName(rr.name))
            data.append(UInt8(rr.type.rawValue >> 8))
            data.append(UInt8(rr.type.rawValue & 0xFF))
            data.append(UInt8(rr.classValue.rawValue >> 8))
            data.append(UInt8(rr.classValue.rawValue & 0xFF))
            data.append(UInt8((rr.ttl >> 24) & 0xFF))
            data.append(UInt8((rr.ttl >> 16) & 0xFF))
            data.append(UInt8((rr.ttl >> 8) & 0xFF))
            data.append(UInt8(rr.ttl & 0xFF))
            let rdlen = UInt16(rr.rdata.count)
            data.append(UInt8(rdlen >> 8))
            data.append(UInt8(rdlen & 0xFF))
            data.append(rr.rdata)
        }
        return data
    }

    public static func parse(_ data: Data) throws -> DNSMessage {
        let (header, consumed) = try DNSHeader.parse(data)
        var offset = consumed

        var questions: [DNSQuestion] = []
        for _ in 0..<header.questionCount {
            let (name, nameLen) = try parseDomainName(data, offset: offset)
            offset += nameLen
            guard data.count >= offset + 4 else { throw DNSError.malformedMessage("question too short") }
            let qtype = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let qclass = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
            offset += 4
            questions.append(DNSQuestion(
                name: name,
                type: DNSRecordType.from(qtype) ?? .a,
                classValue: DNSClass(rawValue: qclass) ?? .inet
            ))
        }

        func parseRecords(count: UInt16) throws -> ([DNSResourceRecord], Int) {
            var records: [DNSResourceRecord] = []
            var pos = offset
            for _ in 0..<count {
                let (name, nameLen) = try parseDomainName(data, offset: pos)
                pos += nameLen
                guard data.count >= pos + 10 else { throw DNSError.malformedMessage("record too short") }
                let rtype = UInt16(data[pos]) << 8 | UInt16(data[pos + 1])
                let rclass = UInt16(data[pos + 2]) << 8 | UInt16(data[pos + 3])
                let ttl = UInt32(data[pos + 4]) << 24 | UInt32(data[pos + 5]) << 16 |
                          UInt32(data[pos + 6]) << 8 | UInt32(data[pos + 7])
                let rdlen = UInt16(data[pos + 8]) << 8 | UInt16(data[pos + 9])
                pos += 10
                guard data.count >= pos + Int(rdlen) else { throw DNSError.malformedMessage("rdata truncated") }
                let rdata = data[pos..<(pos + Int(rdlen))]
                pos += Int(rdlen)
                records.append(DNSResourceRecord(
                    name: name,
                    type: DNSRecordType.from(rtype) ?? .a,
                    classValue: DNSClass(rawValue: rclass) ?? .inet,
                    ttl: ttl,
                    rdata: Data(rdata)
                ))
            }
            return (records, pos)
        }

        let (answers, ansEnd) = try parseRecords(count: header.answerCount)
        offset = ansEnd
        let (authorities, authEnd) = try parseRecords(count: header.authorityCount)
        offset = authEnd
        let (additionals, addEnd) = try parseRecords(count: header.additionalCount)

        return DNSMessage(
            header: header, questions: questions, answers: answers,
            authorities: authorities, additionals: additionals
        )
    }
}

enum DNSError: Error, Equatable, Sendable {
    case malformedMessage(String)
    case timeout
    case serverError(String)
    case noRecords
}

private func encodeDomainName(_ name: String) throws -> Data {
    var data = Data()
    let labels = name.split(separator: ".", omittingEmptySubsequences: false)
    for label in labels {
        guard label.utf8.count <= 63 else {
            throw DNSError.malformedMessage("label exceeds 63 bytes")
        }
        data.append(UInt8(label.utf8.count))
        data.append(contentsOf: label.utf8)
    }
    data.append(0)
    return data
}

private func parseDomainName(_ data: Data, offset: Int) throws -> (name: String, consumed: Int) {
    var labels: [String] = []
    var pos = offset
    var visited = Set<Int>()
    var jumped = false
    var resultOffset = offset

    while pos < data.count {
        guard !visited.contains(pos) else {
            throw DNSError.malformedMessage("circular pointer in domain name")
        }
        visited.insert(pos)

        let len = Int(data[pos])
        if len == 0 {
            pos += 1
            if !jumped { resultOffset = pos }
            break
        } else if (len & 0xC0) == 0xC0 {
            guard pos + 1 < data.count else {
                throw DNSError.malformedMessage("truncated compression pointer")
            }
            let pointer = (Int(data[pos] & 0x3F) << 8) | Int(data[pos + 1])
            if !jumped { resultOffset = pos + 2 }
            pos = pointer
            jumped = true
        } else if len <= 63 {
            pos += 1
            guard pos + len <= data.count else {
                throw DNSError.malformedMessage("label extends beyond message")
            }
            let label = String(data: data[pos..<(pos + len)], encoding: .utf8) ?? ""
            labels.append(label)
            pos += len
        } else {
            throw DNSError.malformedMessage("invalid label length \(len)")
        }
    }

    return (labels.joined(separator: "."), resultOffset - offset)
}
