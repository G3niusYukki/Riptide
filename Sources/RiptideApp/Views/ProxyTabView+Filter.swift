import Foundation
import Riptide

enum ProxySortOrder: String, CaseIterable, Identifiable {
    case `default` = "默认"
    case delayAscending = "延迟↑"
    case delayDescending = "延迟↓"
    case name = "名称"

    var id: String { rawValue }
}

enum ProxyFilter: Hashable {
    case all
    case available
    case region(String)  // ISO code
    case protocolKind(ProxyKind)
}

enum ProxyTabFilter {
    static func sort(_ nodes: [ProxyNodeDisplay], by order: ProxySortOrder) -> [ProxyNodeDisplay] {
        switch order {
        case .default:
            return nodes
        case .delayAscending:
            return nodes.sorted { ($0.delayMs ?? Int.max) < ($1.delayMs ?? Int.max) }
        case .delayDescending:
            return nodes.sorted { ($0.delayMs ?? 0) > ($1.delayMs ?? 0) }
        case .name:
            return nodes.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    static func filter(_ nodes: [ProxyNodeDisplay], by filter: ProxyFilter) -> [ProxyNodeDisplay] {
        switch filter {
        case .all:
            return nodes
        case .available:
            return nodes.filter { $0.status == .available }
        case .region(let code):
            return nodes.filter { RegionMapping.isoCode(for: $0.name) == code }
        case .protocolKind(let kind):
            return nodes.filter { $0.kind == kind }
        }
    }

    static func applySortAndFilter(
        _ nodes: [ProxyNodeDisplay],
        sort: ProxySortOrder,
        filter: ProxyFilter,
        searchText: String
    ) -> [ProxyNodeDisplay] {
        var result = filter == .all ? nodes : ProxyTabFilter.filter(nodes, by: filter)
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if sort != .default {
            result = ProxyTabFilter.sort(result, by: sort)
        }
        return result
    }
}
