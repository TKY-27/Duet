import AppKit
import Foundation

/// Turns repo-relative file paths inside coordination messages into tappable links that open
/// the real file. Security model: a token only becomes a link if it resolves to a file that
/// exists **strictly inside** repoPath. Arbitrary absolute paths from message text are never
/// opened.
enum PathLinker {
    static let scheme = "duet-file"

    private static let knownExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "json", "md", "markdown", "txt",
        "py", "go", "rs", "rb", "java", "kt", "kts", "c", "h", "cc", "cpp", "hpp", "m", "mm",
        "cs", "php", "sh", "bash", "zsh", "yml", "yaml", "toml", "ini", "cfg", "xml", "html",
        "css", "scss", "sql", "gradle", "plist", "lock", "gitignore", "env",
    ]

    private static let pattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:\.?/)?(?:[\w.+\-]+/)*[\w.+\-]+\.[A-Za-z0-9]{1,8}"#
    )

    /// Renders message text with in-repo file paths linked via the custom `duet-file` scheme.
    static func attributedMessage(_ text: String, repoPath: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard !repoPath.isEmpty, let pattern else { return attributed }
        // Apply links to the exact ranges the regex matched. Searching the string for each
        // token would clobber a longer path's suffix when a basename also appears (e.g.
        // linking "foo.swift" inside "src/foo.swift").
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var linkCache: [String: URL?] = [:]
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range])
            // Only bother resolving tokens that look like paths: a slash or a known extension.
            guard token.contains("/") || knownExtensions.contains(fileExtension(of: token)) else { continue }
            let link = linkCache[token] ?? {
                let resolved = linkURL(for: token, repoPath: repoPath)
                linkCache[token] = resolved
                return resolved
            }()
            guard let link else { continue }
            guard let start = AttributedString.Index(range.lowerBound, within: attributed),
                  let end = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[start..<end].link = link
            attributed[start..<end].underlineStyle = .single
        }
        return attributed
    }

    /// Resolve a token to an absolute file URL only when it exists strictly inside repoPath.
    static func resolvedFileURL(_ token: String, repoPath: String) -> URL? {
        guard !repoPath.isEmpty else { return nil }
        let repoURL = URL(fileURLWithPath: repoPath).standardizedFileURL
        let trimmed = token.hasPrefix("./") ? String(token.dropFirst(2)) : token
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = repoURL.appendingPathComponent(trimmed).standardizedFileURL
        }
        guard isInside(candidate, root: repoURL) else { return nil }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    /// Open a `duet-file` link, re-verifying the repoPath boundary before touching the disk.
    @discardableResult
    static func open(_ url: URL, repoPath: String) -> Bool {
        guard url.scheme == scheme else { return false }
        // The link carries the absolute path; re-resolve from scratch as defense in depth in
        // case repoPath changed between render and click.
        guard let fileURL = resolvedFileURL(url.path, repoPath: repoPath) else { return false }
        return NSWorkspace.shared.open(fileURL)
    }

    private static func linkURL(for token: String, repoPath: String) -> URL? {
        guard let fileURL = resolvedFileURL(token, repoPath: repoPath) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.path = fileURL.path
        return components.url
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path == root.path || url.path.hasPrefix(rootPath)
    }

    private static func fileExtension(of value: String) -> String {
        guard let dot = value.lastIndex(of: ".") else { return "" }
        return String(value[value.index(after: dot)...]).lowercased()
    }
}
