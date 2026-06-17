import Foundation
import Yams

public enum OverrideMerger {

    /// Merge `baseYAML` and `overrideYAML` per Override schema (see D2 ADR).
    /// Pure function: no I/O, no actor. Deterministic.
    public static func merge(baseYAML: String, overrideYAML: String) throws -> String {
        let baseMap = try parseMap(yaml: baseYAML, label: "base")
        let trimmed = overrideYAML.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try serialize(map: baseMap)
        }
        let overrideMap = try parseMap(yaml: overrideYAML, label: "override")
        let merged = try mergeMaps(base: baseMap, override: overrideMap)
        return try serialize(map: merged)
    }

    // MARK: - Parsing / Serialization

    private static func parseMap(yaml: String, label: String) throws -> [String: Any] {
        do {
            guard let map = try Yams.load(yaml: yaml) as? [String: Any] else {
                throw OverrideApplyError.invalidYAML("\(label) is not a YAML mapping")
            }
            return map
        } catch let err as OverrideApplyError {
            throw err
        } catch {
            throw OverrideApplyError.invalidYAML("\(label): \(error.localizedDescription)")
        }
    }

    private static func serialize(map: [String: Any]) throws -> String {
        do {
            return try Yams.dump(object: map)
        } catch {
            throw OverrideApplyError.invalidYAML("serialize: \(error.localizedDescription)")
        }
    }

    // MARK: - Map merge

    private static func mergeMaps(base: [String: Any], override: [String: Any]) throws -> [String: Any] {
        // Override wins on scalar sections; lists are appended (or
        // replaced by name when meta.replace is true); nested maps recurse.
        var result = base
        let meta = override["meta"] as? [String: Any] ?? [:]
        let replaceMode = (meta["replace"] as? Bool) ?? false
        let removedList = (override["removed"] as? [String]) ?? []

        for (key, overrideValue) in override {
            if key == "meta" || key == "removed" { continue }

            guard let baseValue = base[key] else {
                result[key] = overrideValue
                continue
            }

            result[key] = try mergeValue(
                key: key,
                base: baseValue,
                override: overrideValue,
                replaceMode: replaceMode
            )
        }

        // Apply removed: across all sections of the result
        if !removedList.isEmpty {
            result = try applyRemovals(map: result, names: removedList)
        }

        return result
    }

    private static func mergeValue(
        key: String,
        base: Any,
        override: Any,
        replaceMode: Bool
    ) throws -> Any {
        // Map + Map → deep merge
        if let baseMap = base as? [String: Any], let overrideMap = override as? [String: Any] {
            var out = baseMap
            for (mapKey, mapValue) in overrideMap {
                if let existing = baseMap[mapKey] {
                    out[mapKey] = try mergeValue(key: "\(key).\(mapKey)", base: existing, override: mapValue, replaceMode: replaceMode)
                } else {
                    out[mapKey] = mapValue
                }
            }
            return out
        }
        // List + List → append (or replace-by-name if replaceMode)
        if let baseList = base as? [Any], let overrideList = override as? [Any] {
            return try mergeLists(
                key: key,
                base: baseList,
                override: overrideList,
                replaceMode: replaceMode
            )
        }
        // Type mismatch
        if type(of: base) != type(of: override) {
            throw OverrideApplyError.typeMismatch(
                section: key,
                baseType: String(describing: type(of: base)),
                overrideType: String(describing: type(of: override))
            )
        }
        // Scalar → override wins
        return override
    }

    private static func mergeLists(
        key: String,
        base: [Any],
        override: [Any],
        replaceMode: Bool
    ) throws -> [Any] {
        if !replaceMode {
            // Append
            return base + override
        }
        // Replace-by-name: for each override dict, if a base dict has the
        // same "name" key, replace it in place; otherwise append.
        var result = base
        for overrideItem in override {
            guard let overrideDict = overrideItem as? [String: Any],
                  let overrideName = overrideDict["name"] as? String else {
                // Override item is not a dict with a name; just append.
                result.append(overrideItem)
                continue
            }
            if let idx = result.firstIndex(where: { ($0 as? [String: Any])?["name"] as? String == overrideName }) {
                result[idx] = overrideDict
            } else {
                result.append(overrideDict)
            }
        }
        return result
    }

    private static func applyRemovals(map: [String: Any], names: [String]) throws -> [String: Any] {
        var result = map
        var matchedAny = false
        for name in names {
            var nameMatched = false
            for (key, value) in map {
                if var list = value as? [Any] {
                    let originalCount = list.count
                    list.removeAll { item in
                        if let dict = item as? [String: Any] {
                            return (dict["name"] as? String) == name
                        }
                        return false
                    }
                    if list.count != originalCount {
                        result[key] = list
                        nameMatched = true
                        matchedAny = true
                    }
                }
            }
            if !nameMatched {
                throw OverrideApplyError.removedNotFound(name: name)
            }
        }
        _ = matchedAny
        return result
    }
}

// MARK: - Runtime helper

/// Compose a base profile's YAML with a sequence of overrides, applying them in order.
/// This is the single call site that future runtime code (e.g. MihomoConfigGenerator)
/// can use to obtain the "effective" YAML for the active profile + active overrides.
public func composeYAML(baseYAML: String, overrides: [Override]) throws -> String {
    try overrides.reduce(baseYAML) { acc, override in
        try OverrideMerger.merge(baseYAML: acc, overrideYAML: override.rawYAML)
    }
}
