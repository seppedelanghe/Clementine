# Goal

Clementine is an open-source macOS menu-bar app that converts files and runs quick actions on
them in the middle of a drag, without opening a window or leaving Finder.

## The interaction

1. Start dragging one or more files anywhere — Finder, the desktop, any app.
2. Tap a modifier key. A radial wheel opens at the cursor, showing what can be done with the
   dragged files.
3. Drop the files on a wedge. The conversion or action runs; converted files are written next
   to the originals.

Each modifier opens a different wheel. The wheel stays open until the files are dropped or the
wheel is cancelled with Escape; dropping anywhere outside it is an ordinary drop.

## Principles

- **Local only.** Files never leave the Mac. No accounts, no network calls besides update checks.
- **Never modify the original.** Every conversion writes a new file.
- **Native.** Swift, with SwiftUI for the shell and settings and AppKit where SwiftUI can't
  reach (global event monitoring, the overlay wheel, drag and drop).
- **macOS first.** Use system frameworks (ImageIO, AVFoundation, PDFKit, …) before bundling
  anything. A bundled tool or library is added only for formats the system cannot handle.
- **Converters are pluggable.** Each converter declares the types it reads and the formats it
  writes; the wheel only asks the registry. Adding a format family never touches the shell.

## Distribution

- Open source, released as a signed app on GitHub Releases. Sparkle for updates if needed.
- Not sandboxed, not on the Mac App Store.
- Minimum macOS 14.

## Non-goals

- File editing tools (cropping, trimming, compression, annotation, redaction and the like).
- Conversion settings beyond sensible fixed defaults.
- Cloud or online conversion.
