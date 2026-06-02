import Foundation

public enum OverrideApplyError: Error, Equatable, Sendable {
    case invalidYAML(String)
    case typeMismatch(section: String, baseType: String, overrideType: String)
    case missingName(field: String, index: Int)
    case removedNotFound(name: String)
}

extension OverrideApplyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidYAML(let detail):
            return "Invalid override YAML: \(detail)"
        case .typeMismatch(let section, let baseType, let overrideType):
            return "Type mismatch on section '\(section)': base is \(baseType), override is \(overrideType)"
        case .missingName(let field, let index):
            return "Missing 'name' key in \(field) at index \(index)"
        case .removedNotFound(let name):
            return "removed: list references name '\(name)' not found anywhere in the merged result"
        }
    }
}
