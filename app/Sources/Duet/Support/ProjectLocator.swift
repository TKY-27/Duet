import Foundation

enum ProjectLocator {
    static func projectRoot() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["DUET_REPO_ROOT"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }

        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("CLAUDE.md").path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        current = executable.deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("CLAUDE.md").path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }
}
