# Scope

The first version exists to get the app shell right: drag detection, the wheel, the converter
registry and file handling. It deliberately uses only macOS system frameworks — nothing is
bundled.

## Convert wheel (Shift)

| Family | Input                              | Output                     | Framework    |
|--------|------------------------------------|----------------------------|--------------|
| Images | JPG, PNG, HEIC, TIFF, GIF, BMP, WebP | JPG, PNG, HEIC, TIFF, PDF | ImageIO      |
| Video  | MOV, MP4, M4V                      | MP4, MOV, M4A (audio only) | AVFoundation |
| Audio  | MP3, M4A, WAV, AIFF, AAC, FLAC     | M4A, WAV, AIFF             | AVFoundation |

## Quick actions wheel (Control)

- **Copy Path** — copies the paths of the dragged files, one per line.
- **AirDrop** — opens the AirDrop share sheet with the dragged files.

## Behaviour

- Output is written next to the original, same base name, new extension. On a name collision,
  Finder-style numbering: `name 2.png`, `name 3.png`, …
- Fixed defaults per output format (e.g. JPEG quality 0.85). No per-conversion options.
- With multiple files dropped, the wheel offers only the outputs every file supports.
- A format is never offered as a conversion to itself.
- Conversions in a batch are independent: one failure doesn't stop the rest. Failures are
  reported in a notification.
- Settings: launch at login, and the modifier key for each wheel.

## Deferred

Each of these is a later, self-contained addition to the converter registry or the actions list.

| Item                                           | Planned approach                                  |
|------------------------------------------------|---------------------------------------------------|
| WebP, AVIF, JXL output                         | libwebp, libavif, libjxl                          |
| MP3 output, MKV, WebM, OGG, Opus, AVI, GIF from video | Bundled ffmpeg                             |
| Archives (ZIP, TAR, GZIP; RAR and 7z input)    | System `bsdtar` / libarchive, 7-Zip for 7z        |
| Subtitles (SRT, VTT, TXT)                      | Own parser                                        |
| Text documents (DOCX, RTF, HTML, MD, TXT, PDF) | NSAttributedString and PDFKit, pandoc if needed   |
| Office and iWork documents                     | Undecided; high-fidelity rendering is costly      |
| Copy and Move actions                          | Folder picker                                     |
| Float (a floating shelf of files)              | Own window                                        |
| Keyboard path (Enter on a Finder selection)    | Needs Finder selection access                     |

## Open questions

- Whether releases will be notarized. That needs a paid Apple Developer account; without it,
  users have to approve the app manually on first launch.
