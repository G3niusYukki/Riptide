import SwiftUI
import Riptide

/// View for displaying configuration validation issues
struct ValidationErrorView: View {
    let result: ConfigValidationResult
    var onDismiss: (() -> Void)?

    private var hasErrors: Bool {
        !result.errors.isEmpty
    }

    private var hasWarnings: Bool {
        !result.warnings.isEmpty
    }

    private var hasInfo: Bool {
        !result.info.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerView

                Divider()
                    .background(Theme.subtext.opacity(0.3))

                // Summary
                summaryView

                Divider()
                    .background(Theme.subtext.opacity(0.3))

                // Issues list
                if result.issues.isEmpty {
                    noIssuesView
                } else {
                    issuesListView
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private var headerView: some View {
        HStack {
            Image(systemName: hasErrors ? "xmark.circle.fill" : (hasWarnings ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                .font(.title)
                .foregroundStyle(hasErrors ? Theme.danger : (hasWarnings ? Theme.warning : Theme.success))

            VStack(alignment: .leading, spacing: 4) {
                Text("Configuration Validation")
                    .font(.headline)
                    .foregroundStyle(Theme.text)

                Text(hasErrors ? "Errors found" : (hasWarnings ? "Warnings found" : "Validation passed"))
                    .font(.subheadline)
                    .foregroundStyle(hasErrors ? Theme.danger : (hasWarnings ? Theme.warning : Theme.success))
            }

            Spacer()

            if let onDismiss = onDismiss {
                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var summaryView: some View {
        HStack(spacing: 16) {
            SummaryBadge(
                count: result.errors.count,
                label: "Errors",
                color: Theme.danger,
                icon: "xmark.circle"
            )

            SummaryBadge(
                count: result.warnings.count,
                label: "Warnings",
                color: Theme.warning,
                icon: "exclamationmark.triangle"
            )

            SummaryBadge(
                count: result.info.count,
                label: "Info",
                color: Theme.accent,
                icon: "info.circle"
            )
        }
    }

    private var noIssuesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.success)

            Text("No issues found")
                .font(.headline)
                .foregroundStyle(Theme.text)

            Text("The configuration appears to be valid.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var issuesListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Errors section
            if hasErrors {
                IssueSection(
                    title: "Errors",
                    icon: "xmark.circle.fill",
                    color: Theme.danger,
                    issues: result.errors
                )
            }

            // Warnings section
            if hasWarnings {
                IssueSection(
                    title: "Warnings",
                    icon: "exclamationmark.triangle.fill",
                    color: Theme.warning,
                    issues: result.warnings
                )
            }

            // Info section
            if hasInfo {
                IssueSection(
                    title: "Information",
                    icon: "info.circle.fill",
                    color: Theme.accent,
                    issues: result.info
                )
            }
        }
    }
}

/// Summary badge showing count and label
private struct SummaryBadge: View {
    let count: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)

            Text("\(count)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.text)

            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// Section of issues with a specific severity
private struct IssueSection: View {
    let title: String
    let icon: String
    let color: Color
    let issues: [ValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)

                Spacer()
            }
            .padding(.bottom, 4)

            ForEach(issues) { issue in
                IssueRow(issue: issue, color: color)
            }
        }
    }
}

/// Row displaying a single validation issue
private struct IssueRow: View {
    let issue: ValidationIssue
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Path and line info
            HStack {
                Text(issue.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.accent)

                Spacer()

                if let line = issue.line {
                    Text("Line \(line)")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }

                if let column = issue.column {
                    Text("Col \(column)")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
            }

            // Message
            Text(issue.message)
                .font(.body)
                .foregroundStyle(Theme.text)

            // Suggestion (if available)
            if let suggestion = issue.suggestion {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)

                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

// MARK: - Preview

#Preview("With Errors and Warnings") {
    let sampleIssues: [ValidationIssue] = [
        ValidationIssue(
            line: 15,
            column: 8,
            severity: .error,
            message: "Duplicate proxy name: US-Server-01",
            path: "proxies[3].name",
            suggestion: "Use a unique name for each proxy"
        ),
        ValidationIssue(
            line: 42,
            severity: .error,
            message: "Port 70000 is out of valid range (1-65535)",
            path: "proxies[5].port",
            suggestion: "Use a port between 1 and 65535"
        ),
        ValidationIssue(
            line: 78,
            severity: .warning,
            message: "Unknown Shadowsocks cipher: aes-512-gcm",
            path: "proxies[8].cipher",
            suggestion: "Valid ciphers: aes-128-gcm, aes-192-gcm, aes-256-gcm, chacha20-ietf-poly1305..."
        ),
        ValidationIssue(
            line: 105,
            severity: .warning,
            message: "Proxy 'Singapore-Node' referenced in group but not defined",
            path: "proxy-groups[1].proxies[2]",
            suggestion: "Add 'Singapore-Node' to proxies section or correct the name"
        )
    ]

    return ValidationErrorView(
        result: ConfigValidationResult(issues: sampleIssues),
        onDismiss: {}
    )
    .frame(width: 500, height: 600)
}

#Preview("Valid Config") {
    ValidationErrorView(
        result: ConfigValidationResult(issues: []),
        onDismiss: {}
    )
    .frame(width: 500, height: 400)
}

#Preview("Only Warnings") {
    let warnings: [ValidationIssue] = [
        ValidationIssue(
            severity: .warning,
            message: "Unknown mode: smart",
            path: "mode",
            suggestion: "Valid modes: rule, global, direct"
        )
    ]

    return ValidationErrorView(
        result: ConfigValidationResult(issues: warnings),
        onDismiss: {}
    )
    .frame(width: 500, height: 300)
}
