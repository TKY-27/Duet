# Duet Design Principles

This document is the standing brief for Duet's interface. It exists because the
first version of the SwiftUI app was a one-to-one port of an HTML prototype, and
it showed: Duet looked like a screenshot of a web app rather than a Mac
application.

It is written to be read before changing any rendered surface, not after.

## The problem this document guards against

The prevailing name for the failure mode is **AI slop**. The useful definition
is not "ugly": it is **design with no author** — the statistical average of many
thousands of interfaces, rendered cleanly and shipped without anyone asking
whether it should look and feel like this. Slop is rarely misaligned or broken.
It is *anonymous*. The tell is that nothing in it required a decision.

The commonly catalogued fingerprints are worth naming so they can be refused on
sight:

- an indigo-to-purple gradient, especially behind a hero or a primary button
- a 1px grey border around every card, and a card around everything
- three or six identical tiles in a row, each an icon plus a heading plus two
  lines of text
- glassmorphism used as decoration, with a glow behind it
- a bounce or scale on every hover
- dark mode nobody asked for, offered as a toggle
- and, most reliably: **no empty state, no error state, no focus state**. Only
  the happy path was ever designed.

Duet's first release contained most of these. They are recorded in the table
below with what replaced them, so the same decisions are not silently undone.

## What replaced what

| Removed | Reason | Replacement |
| --- | --- | --- |
| Hand-built window chrome (`VStack { toolbar; HStack { sidebar; log }; input }`) | Reimplemented the window badly, and could not inherit any system behaviour | Real `NavigationSplitView`, real `.toolbar`, real `.inspector` |
| A 19-property palette of literal RGB triples, in three variants | Ignored system appearance, accent colour, and increased-contrast settings | Semantic system colours plus a small named ramp in an asset catalog, with light/dark/increased-contrast variants |
| A "terminal" green theme | Decoration with no function; a third surface to maintain and test | Removed. Duet follows the system appearance |
| Chat bubbles with left/right alternation and accent-tinted fills | An iMessage costume on a coordination log; wasted horizontal space and broke down on long messages | Single-column typographic transcript with a speaker gutter |
| Corner radii of 8, 11, 12, and 14 chosen per-view | No system; four values doing one job | Structure carried by rules and whitespace. Radius is the exception, not the default |
| `.overlay(RoundedRectangle().stroke(...))` on nearly every container | Borders drawn where no edge exists | Separators and spacing |
| Font sizes 10.5, 11.5, 12.5, 13.5, 14 as literals | Not a scale; nothing relates to anything | A named type scale built on semantic text styles, so it tracks the system text-size setting |
| `.bold` / `.black` / `.tracking(0.4)` / `.textCase(.uppercase)` micro-labels | The "tiny shouting label" tic; poor legibility at small sizes | Hierarchy from size and spacing; sentence case |
| An in-app theme picker and language picker in the toolbar | Duplicated OS settings and added permanent chrome | System appearance and system language |
| A hand-rolled `L10n` enum with a `switch` per string | Unmaintainable, and could not follow the system language properly | String Catalog (`.xcstrings`) |

## Principles

**Structure is Apple's, not ours.** Sidebar leading, inspector trailing-most in
the toolbar, menu bar as a first-class command surface. A Mac app that invents
its own window furniture is worse than one that uses the system's, however
carefully the invention is drawn.

**Colour must mean something.** In Duet, colour is spent on exactly two things:
agent identity and state. There is no decorative colour. If a new colour cannot
name what it distinguishes, it does not get added.

**Type carries the hierarchy.** The transcript is a reading surface. Measure,
leading, and spacing do the work that boxes and rules were doing before.

**Every state is designed.** Empty, connecting, waiting, stalled, disconnected,
sending, failed, and history-unavailable are all real states of this product.
They are specified alongside the happy path, not discovered in QA. This is the
single most reliable difference between authored software and slop.

**Motion is information.** Movement is used when something arrived, changed, or
moved — never as texture. Reduce Motion is honoured.

**Liquid Glass is for the navigation layer only.** On macOS 26 the toolbar,
sidebar, and inspector may float above content. The transcript, lists, and any
scrolling content stay opaque. Glass stacked on glass, or glass behind reading
text, is exactly the decoration this document rejects.

## Accessibility is part of the design, not a pass afterwards

Every rendered change is checked against: system text-size scaling, Reduce
Motion, Reduce Transparency, Increase Contrast, full keyboard reachability,
VoiceOver reading order, and both `ja` and `en` locales. A successful build is
not visual verification, and neither is a screenshot in one configuration.

## Reference points

Structure comes from Apple's Human Interface Guidelines for macOS. For density
and typographic craft, the useful reference apps are the designer-led Mac tools
— Things, Linear, Tower, Kaleidoscope. What is worth taking from them is not
their appearance but three habits: an authored type scale, colour spent only on
meaning, and information density achieved without visual noise.

Do not copy another product's look. Copying Linear's palette produces a
different flavour of the same anonymity this document is about.
