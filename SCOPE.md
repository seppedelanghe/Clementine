# Scope

The first version exists to get the app shell right: drag detection, the wheel, the converter
registry and file handling. macOS system frameworks handle what they can; a bundled LGPL ffmpeg
(see `docs/ffmpeg.md`) takes every other audio and video conversion.

## Convert wheel (Shift)

| Family | Input                              | Output                     | Framework    |
|--------|------------------------------------|----------------------------|--------------|
| Images | JPG, PNG, HEIC, TIFF, GIF, BMP, WebP | JPG, PNG, HEIC, TIFF, PDF | ImageIO      |
| Video  | MOV, MP4, M4V                      | MP4, MOV, M4A (audio only) | AVFoundation |
| Audio  | MP3, M4A, WAV, AIFF, AAC, FLAC     | M4A, WAV, AIFF, FLAC       | AVFoundation |
| Video  | Any movie ffmpeg reads (MKV, WebM, AVI, WMV, …) | MP4, MOV, MKV, WebM, AVI, WMV, GIF, M4A, MP3 | ffmpeg |
| Audio  | Any audio ffmpeg reads (OGG, Opus, WMA, …) | MP3, M4A, WAV, AIFF, FLAC, OGG, Opus, WMA | ffmpeg |

## Quick actions wheel (Control)

- **Copy** — copies the dragged files themselves, like Copy in Finder.
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
| Archives (ZIP, TAR, GZIP; RAR and 7z input)    | System `bsdtar` / libarchive, 7-Zip for 7z        |
| Subtitles (SRT, VTT, TXT)                      | Own parser                                        |
| Text documents (DOCX, RTF, HTML, MD, TXT, PDF) | NSAttributedString and PDFKit, pandoc if needed   |
| Office and iWork documents                     | Undecided; high-fidelity rendering is costly      |
| Move action                                    | Folder picker                                     |
| Float (a floating shelf of files)              | Own window                                        |
| Keyboard path (Enter on a Finder selection)    | Needs Finder selection access                     |

## Open questions

- Whether releases will be notarized. That needs a paid Apple Developer account; without it,
  users have to approve the app manually on first launch.
