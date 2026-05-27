import Foundation

public enum ConfigDiff {
    /// Generates a unified diff between original and merged YAML.
    /// Returns nil when the content is identical or the system diff command fails.
    public static func computeUnifiedDiff(original: String, merged: String) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let originalFile = tempDir.appendingPathComponent("riptide-original-\(UUID().uuidString).yaml")
        let mergedFile = tempDir.appendingPathComponent("riptide-merged-\(UUID().uuidString).yaml")

        do {
            try original.write(to: originalFile, atomically: true, encoding: .utf8)
            try merged.write(to: mergedFile, atomically: true, encoding: .utf8)

            defer {
                try? FileManager.default.removeItem(at: originalFile)
                try? FileManager.default.removeItem(at: mergedFile)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
            process.arguments = ["-u", originalFile.path, mergedFile.path]

            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 1 else {
                return nil
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: originalFile)
            try? FileManager.default.removeItem(at: mergedFile)
            return nil
        }
    }
}
