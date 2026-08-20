# Measured Preconditions

These are machine measurements taken before implementing the corresponding
features. They are implementation preconditions and a record of what was
actually observed — not evidence that the features are ready, and not a claim
that they still hold on a different machine or a newer version of either
desktop app. Re-measure before relying on any of them.

## Phase 3 OCR Preconditions

These values were measured on this machine on 2026-06-01 before implementing
the OCR insurance layer. They are implementation preconditions, not proof that
OCR capture quality or OCR accuracy is ready.

Installed application paths were checked with:

- `ls /Applications | grep -i -E "codex|claude"` -> `Claude.app`, `Codex.app`

Bundle identifiers were measured from the installed application bundles:

- `mdls -name kMDItemCFBundleIdentifier /Applications/Codex.app` ->
  `com.openai.codex`
- `mdls -name kMDItemCFBundleIdentifier /Applications/Claude.app` ->
  `com.anthropic.claudefordesktop`

The sandboxed `mdls` invocation reported the existing paths as not found, so the
same `mdls` commands were rerun outside the sandbox. `plutil -extract
CFBundleIdentifier raw .../Contents/Info.plist` returned the same identifiers.

ScreenCaptureKit window enumeration was probed with a temporary Swift snippet
under `tools/` that only called `SCShareableContent` and logged
`SCWindow.owningApplication.bundleIdentifier`; it did not capture images, run
Vision OCR, save screenshots, send messages, or update the GUI. The temporary
probe file was not retained in the repository. The snippet was compiled with:

- `swiftc -module-cache-path .build/module-cache -o
  .build/scshareable-window-list tools/scshareable-window-list.swift`

In this command execution context, `CGPreflightScreenCaptureAccess()` returned
`false`, and the probe printed:

- `screenCaptureAccess=false`
- `SCShareableContent enumeration skipped: Screen Recording permission is not
  granted for this executable context.`

An earlier run without the preflight check produced no output and was stopped,
which is consistent with a Screen Recording permission or TCC wait in this
context. Because Screen Recording permission was not granted here,
`SCShareableContent` has not yet confirmed live Codex or Claude windows by
bundle identifier on this machine. Phase 3 must keep an explicit permission
preflight path and rerun window enumeration after Screen Recording is granted to
the executable context that performs OCR.

As a fallback candidate only, a `CGWindowListCopyWindowInfo` plus
`NSRunningApplication(processIdentifier:)` probe was also compiled and run
without capture. In this same command execution context it returned
`totalOnScreenWindowCount=0`, so it did not confirm Codex or Claude windows.
If ScreenCaptureKit cannot identify windows by
`owningApplication.bundleIdentifier` after permission is granted, the next
fallback to evaluate is process-id mapping from ScreenCaptureKit or
CoreGraphics window metadata to `NSRunningApplication`, then filtering by the
measured bundle identifiers above.

## Phase 4 Wakeup Preconditions

These values were measured on this machine on 2026-06-02 before implementing
any wake-up automation. They are implementation preconditions, not a shipped
wake-up feature.

Claude URL scheme registration:

- `plutil -p /Applications/Claude.app/Contents/Info.plist | rg -n -C 8
  "CFBundleURLTypes|CFBundleURLSchemes|claude|CFBundleIdentifier"` confirmed
  `CFBundleIdentifier = "com.anthropic.claudefordesktop"` and
  `CFBundleURLSchemes = ["claude"]`.
- Launch Services also reported Claude as a handler for `claude:` through
  `lsregister -dump | rg -n -C 4
  "bindings:.*claude:|scheme: claude|claude://|com\\.anthropic\\.claudefordesktop|Claude\\.app"`.

Claude prompt injection:

- The tested command was
  `/usr/bin/open 'claude://code/new?q=ping%20from%20duet%20wakeup%20test'`.
- After opening Claude and recapturing the screen, the text
  `ping from duet wakeup test` was present in the Claude Code input field.
- It was not submitted automatically. The prompt remained a draft in the input
  field, and no assistant response or running state appeared.
- Therefore Phase 4 must treat Claude URL prompt injection as input-only on this
  machine and must use an explicit Return/Enter completion step if it needs to
  submit the prompt.
- No Accessibility or Automation permission prompt appeared for opening the
  `claude://` URL itself.
- The exact tested URL form is `claude://code/new?q=<url-encoded-prompt>`.
  Continuing an existing Claude Code session through a session-specific
  `claude://` URL was not confirmed and must remain unknown until separately
  measured or documented.

Codex AppleScript prompt injection:

- `osascript -e 'tell application "Codex" to activate' -e 'delay 1' -e
  'tell application "System Events" to keystroke "ping from duet wakeup test"'`
  activated Codex and typed into the active chat input field.
- It did not submit automatically. The send arrow remained available, so
  Return/Enter or an equivalent send action is required to submit.
- In this Japanese input-source environment, direct `keystroke` text was
  transformed by IME candidate handling and did not reliably preserve the exact
  ASCII prompt. Phase 4 should not rely on direct text keystrokes for exact
  prompt injection without first controlling the input source or using a
  separately verified paste path.
- `swift -e 'import ApplicationServices; print(AXIsProcessTrusted())'`
  returned `true` in this command execution context, and the AppleScript command
  succeeded without a new TCC prompt. Denied Accessibility or Automation
  behavior was not measured and remains unknown.
- A later `ping from duet wakeup test` shown as a sent Codex message followed
  user interaction during the experiment interruption, so it is not evidence
  that AppleScript injection alone submits the prompt.
