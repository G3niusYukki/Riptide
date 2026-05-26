import SwiftUI

// MARK: - Diff View

/// A view that displays a unified diff with syntax coloring.
/// Lines starting with `+` are shown in green (additions).
/// Lines starting with `-` are shown in red (deletions).
/// Lines starting with `@@` are shown in blue (hunk headers).
public struct DiffView: View {
    let diffText: String
    let fontSize: CGFloat

    public init(diffText: String, fontSize: CGFloat = 12) {
        self.diffText = diffText
        self.fontSize = fontSize
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(lineColor(for: line.type))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(backgroundColor(for: line.type))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Line Types

    private enum DiffLineType {
        case addition
        case deletion
        case hunkHeader
        case context
        case fileHeader
    }

    private struct DiffLine {
        let type: DiffLineType
        let text: String
    }

    // MARK: - Parsing

    private var diffLines: [DiffLine] {
        let lines = diffText.components(separatedBy: .newlines)
        return lines.map { line in
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                return DiffLine(type: .addition, text: line)
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                return DiffLine(type: .deletion, text: line)
            } else if line.hasPrefix("@@") {
                return DiffLine(type: .hunkHeader, text: line)
            } else if line.hasPrefix("---") || line.hasPrefix("+++") {
                return DiffLine(type: .fileHeader, text: line)
            } else {
                return DiffLine(type: .context, text: line)
            }
        }
    }

    // MARK: - Colors

    private func lineColor(for type: DiffLineType) -> Color {
        switch type {
        case .addition:
            return .green
        case .deletion:
            return .red
        case .hunkHeader:
            return .blue
        case .fileHeader:
            return .secondary
        case .context:
            return .primary
        }
    }

    private func backgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .addition:
            return .green.opacity(0.1)
        case .deletion:
            return .red.opacity(0.1)
        case .hunkHeader:
            return .blue.opacity(0.1)
        case .fileHeader:
            return .secondary.opacity(0.1)
        case .context:
            return .clear
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleDiff = """
    --- original
    +++ merged
    @@ -1,5 +1,7 @@
     mode: rule
     proxies:
       - name: proxy1
    +  - name: proxy2
    +    type: ss
    +    server: 1.2.3.4
         port: 443
     rules:
    -  - MATCH,DIRECT
    +  - DOMAIN-SUFFIX,google.com,PROXY
    +  - MATCH,DIRECT
    """

    DiffView(diffText: sampleDiff)
        .frame(width: 500, height: 300)
        .padding()
}
