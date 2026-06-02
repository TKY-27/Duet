import Foundation

enum DuetErrorRedactor {
    static func redact(_ message: String, projectRoot: URL? = nil) -> String {
        var redacted = message

        if let projectRootPath = projectRoot?.standardizedFileURL.path, !projectRootPath.isEmpty {
            redacted = redacted.replacingOccurrences(of: projectRootPath, with: "<project-root>")
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if !homePath.isEmpty {
            redacted = redacted.replacingOccurrences(of: homePath, with: "~")
        }

        redacted = replaceMatches(in: redacted, pattern: #"(token=)[^&\s)]+"#, template: "$1[redacted]")
        redacted = replaceMatches(in: redacted, pattern: #"(DUET_CONTROL_TOKEN=)[^\s)]+"#, template: "$1[redacted]")
        redacted = replaceMatches(
            in: redacted,
            pattern: #"(X-Duet-Control-Token[\s:=]+)[^\s)]+"#,
            template: "$1[redacted]"
        )

        return redacted
    }

    private static func replaceMatches(in text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

extension HubProcessOutput {
    func redacted(projectRoot: URL) -> HubProcessOutput {
        HubProcessOutput(
            stdout: stdout.map { DuetErrorRedactor.redact($0, projectRoot: projectRoot) },
            stderr: stderr.map { DuetErrorRedactor.redact($0, projectRoot: projectRoot) }
        )
    }
}
