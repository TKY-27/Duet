import AppKit
import SwiftUI

// MARK: - Colour
//
// Duet's palette is the system palette. The previous design hardcoded 19 RGB
// triples across three bespoke themes, which meant the window ignored the
// user's appearance, accent colour, Increase Contrast setting, and vibrancy —
// and looked like a web mockup rather than a Mac app.
//
// Colour here carries meaning and nothing else. There are exactly two
// decorative-looking colours in the app, and both are identity: one per agent.
// Everything else is either a system semantic colour or a state colour.

enum DuetColor {
    // Surfaces and text: all system semantic colours, so they track appearance,
    // Increase Contrast, and vibrancy without any work on our side.
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let contentBackground = Color(nsColor: .textBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)

    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    /// The human's voice in the transcript. Deliberately the user's own accent
    /// colour: the one place the app should feel like *their* Mac.
    static let human = Color(nsColor: .controlAccentColor)

    // State colours. `systemRed`/`systemGreen`/`systemOrange` already have
    // Increase-Contrast variants, so they stay legible without a second palette.
    static let failure = Color(nsColor: .systemRed)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)

    static func agent(_ agent: AgentID) -> Color {
        agent.accent
    }
}

extension ConnectionState {
    var statusColor: Color {
        switch self {
        case .connected: DuetColor.success
        case .connecting, .reconnecting: DuetColor.warning
        case .failed: DuetColor.failure
        case .disconnected: DuetColor.tertiaryText
        }
    }
}

// MARK: - Typography
//
// One authored scale with named roles, built on the semantic text styles so
// every size tracks the user's text-size setting. The old design used literal
// point sizes (10.5, 11.5, 12.5, 13.5) that scaled with nothing.

enum DuetFont {
    /// Transcript body. The one thing in the window that is meant to be *read*,
    /// so it gets the system reading size rather than a shrunken UI size.
    static let body = Font.system(.body)
    /// Speaker name in the transcript gutter.
    static let speaker = Font.system(.subheadline, weight: .semibold)
    /// Role, timestamps, counts — present but never competing with the body.
    static let meta = Font.system(.caption)
    /// Section headers in the inspector.
    static let sectionHeader = Font.system(.subheadline, weight: .semibold)
    /// Field labels above inputs.
    static let fieldLabel = Font.system(.caption)
    /// Paths, branches, diff counts.
    static let mono = Font.system(.caption, design: .monospaced)
    /// Larger monospace for the repository strip.
    static let monoBody = Font.system(.callout, design: .monospaced)
    /// Empty- and error-state headline.
    static let emptyTitle = Font.system(.title3, weight: .medium)
}

// MARK: - Spacing
//
// A 4pt scale. Named by intent so a reviewer can tell whether a number is a
// considered choice or a leftover.

enum DuetSpacing {
    /// Between tightly related items (a label and its value).
    static let hairline: CGFloat = 4
    /// Within a component.
    static let tight: CGFloat = 8
    /// Between components.
    static let regular: CGFloat = 12
    /// Between groups.
    static let loose: CGFloat = 20
    /// Section separation.
    static let section: CGFloat = 32

    /// Transcript gutter width: wide enough for a timestamp at the largest
    /// comfortable text size without the body column shifting as time passes.
    static let gutter: CGFloat = 92
    /// Reading measure for transcript body text. Prose stops being comfortable
    /// past roughly 75 characters, and agent messages are prose.
    static let readingMeasure: CGFloat = 680
}

// MARK: - Motion
//
// Motion is used to explain change and nothing else: a message arriving, a
// state flipping. Every animation here is defined once so Reduce Motion can
// turn the whole set off in one place.

enum DuetMotion {
    static let messageArrival = Animation.easeOut(duration: 0.22)
    static let stateChange = Animation.easeInOut(duration: 0.18)

    /// Returns `nil` when the user has asked for reduced motion, which SwiftUI
    /// treats as "apply the change without animating".
    static func respectingReduceMotion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Shared controls

/// Agent identity mark. Falls back to a monogram when the bundled icon is
/// missing, so a resource problem degrades instead of rendering an empty box.
struct AgentAvatar: View {
    var agent: AgentID
    var size: CGFloat

    var body: some View {
        ZStack {
            if let iconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(agent.accent)
                Text(String(agent.displayName.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var iconImage: NSImage? {
        guard let url = Bundle.module.url(
            forResource: agent.iconResourceName,
            withExtension: "png",
            subdirectory: "Resources/AgentIcons"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

/// A small state dot. Shape carries the meaning for anyone who cannot
/// distinguish the colours: filled means present, hollow means absent.
struct StatusDot: View {
    var color: Color
    var filled: Bool
    var size: CGFloat = 7

    var body: some View {
        Group {
            if filled {
                Circle().fill(color)
            } else {
                Circle().strokeBorder(color, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Text {
    func fieldLabelStyle() -> some View {
        font(DuetFont.fieldLabel).foregroundStyle(DuetColor.secondaryText)
    }
}
