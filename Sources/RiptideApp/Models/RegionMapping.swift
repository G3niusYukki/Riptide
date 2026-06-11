import Foundation

/// Maps node-name keywords to ISO 3166-1 alpha-2 country codes.
/// Order matters: longer/more specific keywords must be checked first
/// (e.g. "英国" before "英" to avoid "英国" being misread).
enum RegionMapping {
    private static let chineseKeywords: [(keyword: String, code: String)] = [
        ("香港", "HK"), ("台湾", "TW"), ("日本", "JP"), ("韩国", "KR"),
        ("新加坡", "SG"), ("美国", "US"), ("加拿大", "CA"),
        ("英国", "GB"), ("德国", "DE"), ("法国", "FR"),
        ("澳大利亚", "AU"), ("俄罗斯", "RU"), ("土耳其", "TR"),
        ("巴西", "BR"), ("印度", "IN"), ("澳门", "MO"),
        ("泰国", "TH"), ("马来西亚", "MY"), ("菲律宾", "PH"),
        ("越南", "VN"), ("印度尼西亚", "ID"),
        ("阿根廷", "AR"), ("智利", "CL"), ("墨西哥", "MX"),
        ("南非", "ZA"), ("以色列", "IL"), ("阿联酋", "AE"),
        ("沙特", "SA"), ("巴基斯坦", "PK"), ("孟加拉", "BD"),
        ("哈萨克斯坦", "KZ"), ("乌克兰", "UA"),
        ("波兰", "PL"), ("西班牙", "ES"), ("意大利", "IT"),
        ("荷兰", "NL"), ("瑞典", "SE"), ("瑞士", "CH"),
    ]

    private static let englishKeywords: [(keyword: String, code: String)] = [
        ("UK", "GB"), ("HongKong", "HK"), ("Hong Kong", "HK"),
        ("Taiwan", "TW"), ("Japan", "JP"), ("Korea", "KR"),
        ("Singapore", "SG"), ("United States", "US"), ("America", "US"),
        ("Canada", "CA"), ("Germany", "DE"), ("France", "FR"),
        ("Australia", "AU"), ("Russia", "RU"), ("Turkey", "TR"),
        ("Brazil", "BR"), ("India", "IN"), ("Thailand", "TH"),
        ("Malaysia", "MY"), ("Philippines", "PH"), ("Vietnam", "VN"),
        ("Indonesia", "ID"), ("Netherlands", "NL"), ("Spain", "ES"),
        ("Italy", "IT"), ("Sweden", "SE"), ("Switzerland", "CH"),
        ("Argentina", "AR"), ("Chile", "CL"), ("Mexico", "MX"),
        ("South Africa", "ZA"), ("Israel", "IL"), ("UAE", "AE"),
        ("Saudi", "SA"), ("Pakistan", "PK"), ("Ukraine", "UA"),
        ("Poland", "PL"), ("Norway", "NO"), ("Finland", "FI"),
        ("Denmark", "DK"), ("Czech", "CZ"), ("Austria", "AT"),
        ("Belgium", "BE"), ("Ireland", "IE"), ("Portugal", "PT"),
        ("Greece", "GR"), ("Romania", "RO"), ("Hungary", "HU"),
        ("Bulgaria", "BG"), ("Croatia", "HR"), ("Slovakia", "SK"),
        ("Slovenia", "SI"), ("Lithuania", "LT"), ("Latvia", "LV"),
        ("Estonia", "EE"), ("Egypt", "EG"), ("Kazakhstan", "KZ"),
        ("Bangladesh", "BD"),
    ]

    private static let isoCodes: Set<String> = [
        "HK", "JP", "US", "SG", "TW", "KR", "IN", "GB", "DE", "FR",
        "CA", "AU", "RU", "TR", "BR", "NL", "TH", "MY", "PH", "VN",
        "ID", "AR", "CL", "CO", "MX", "PE", "EG", "ZA", "IL", "AE",
        "SA", "PK", "BD", "KZ", "UA", "PL", "SE", "NO", "FI", "DK",
        "CZ", "AT", "CH", "BE", "IE", "PT", "ES", "IT", "GR", "RO",
        "HU", "BG", "HR", "SK", "SI", "LT", "LV", "EE", "MO",
    ]

    /// Returns the ISO 3166-1 alpha-2 code for a node name, or nil if no region detected.
    static func isoCode(for nodeName: String) -> String? {
        let lowercased = nodeName.lowercased()

        // Check Chinese keywords first (case-sensitive, since Chinese chars are unique)
        for (keyword, code) in chineseKeywords where nodeName.contains(keyword) {
            return code
        }

        // Check English keywords (case-insensitive, longer keywords first)
        for (keyword, code) in englishKeywords where lowercased.contains(keyword.lowercased()) {
            return code
        }

        // Check bare ISO codes (e.g. "JP-Tokyo", "US-WEST", "US_Los_Angeles")
        for code in isoCodes {
            // Match ISO code delimited by non-letter characters (so JP-Tokyo and US_Los_Angeles both match)
            let pattern = "(?:^|[^a-z])\(code.lowercased())(?:$|[^a-z])"
            if let _ = lowercased.range(of: pattern, options: .regularExpression) {
                return code
            }
        }

        return nil
    }

    /// Returns the Unicode flag emoji for an ISO 3166-1 alpha-2 code.
    static func flagEmoji(for code: String) -> String {
        guard code.count == 2 else { return "🌐" }
        let base: UInt32 = 127397
        var emoji = ""
        for scalar in code.uppercased().unicodeScalars {
            if let combined = UnicodeScalar(base + scalar.value) {
                emoji.unicodeScalars.append(combined)
            }
        }
        return emoji.isEmpty ? "🌐" : emoji
    }
}
