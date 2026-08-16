import Foundation

enum DuetFormatters {
    /// Transcript gutter timestamps. Fixed 24-hour form so the gutter width
    /// does not change with locale or time of day.
    static let messageTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Session list dates. Locale-aware, since this one is read rather than
    /// scanned in a column.
    static let sessionDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

extension String {
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if hasPrefix(home) {
            return "~" + dropFirst(home.count)
        }
        return self
    }
}
