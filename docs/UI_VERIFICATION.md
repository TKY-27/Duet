# Manual UI Verification Checklist

The SwiftUI target builds and has automated tests, but rendered quality still
requires a human pass on macOS. Record the date, macOS version, app commit, and
any failures when completing this checklist.

## Environment matrix

- [ ] Typical window size and the minimum supported window size
- [ ] Light appearance
- [ ] Dark appearance
- [ ] Increase Contrast
- [ ] Reduce Transparency
- [ ] Reduce Motion
- [ ] Enlarged system text / Dynamic Type equivalent on macOS
- [ ] English locale
- [ ] Japanese locale, including long Japanese role/task text
- [ ] Keyboard-only navigation and visible focus
- [ ] VoiceOver reading order and meaningful control labels

## State matrix

- [ ] First launch / missing configuration
- [ ] Hub starting and connecting
- [ ] Hub healthy with both agents absent
- [ ] One agent connected and one agent absent
- [ ] Running with an empty transcript
- [ ] Waiting / progress notification state
- [ ] Stalled agent warning and recovery
- [ ] Disconnected or failed Hub
- [ ] Human message sending and disabled input
- [ ] Repository unavailable, detached, dirty, and long-path states
- [ ] Session history unavailable or empty
- [ ] Long transcript, search, sender filter, and jump-to-latest
- [ ] Setup popover, copy confirmation, and diagnostic details

The checklist is a release gate for a downloadable app, not evidence that the
current development bundle has already received that human verification.
