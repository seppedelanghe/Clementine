# Scope

The first version exists to get the app shell right: drag detection, the wheel, the converter
registry and file handling. macOS system frameworks and tools handle what they can; a bundled LGPL
ffmpeg (see `docs/ffmpeg.md`) takes every other audio and video conversion.

## Convert wheel (Shift)

| Family | Input                              | Output                     | Framework    |
|--------|------------------------------------|----------------------------|--------------|
| Images | JPG, PNG, HEIC, TIFF, GIF, BMP, WebP | JPG, PNG, HEIC, TIFF, PDF | ImageIO      |
| Video  | MOV, MP4, M4V                      | MP4, MOV, M4A (audio only) | AVFoundation |
| Audio  | MP3, M4A, WAV, AIFF, AAC, FLAC     | M4A, WAV, AIFF, FLAC       | AVFoundation |
| Video  | Any movie ffmpeg reads (MKV, WebM, AVI, WMV, …) | MP4, MOV, MKV, WebM, AVI, WMV, GIF, M4A, MP3 | ffmpeg |
| Audio  | Any audio ffmpeg reads (OGG, Opus, WMA, …) | MP3, M4A, WAV, AIFF, FLAC, OGG, Opus, WMA | ffmpeg |
| Archives | ZIP, 7z, RAR, TAR, TAR.GZ, TAR.BZ2, TAR.XZ | ZIP, 7z, TAR, TAR.GZ, TAR.XZ | System `bsdtar` |
| Folders | Any folder                         | ZIP, 7z, TAR.GZ, TAR.XZ    | System `bsdtar` |
| Documents | DOCX, DOC, RTF, ODT, HTML, TXT   | PDF, DOCX, RTF, ODT, HTML, TXT | NSAttributedString |
| Documents | MD                               | PDF, DOCX, RTF, HTML, TXT  | Foundation's Markdown parser |
| Documents | PDF                              | TXT, RTF, DOCX (text only) | PDFKit       |
| Documents | Pages                            | PDF, DOCX, RTF, TXT, EPUB  | Pages, only when installed |

Documents keep text, styles, lists and simple tables. Page layout does not survive: headers and
footers, columns and floating images are lost. Pages files are exported by Pages itself, which
asks once for Automation permission.

## Quick actions wheel (Control)

- **Copy** — copies the dragged files themselves, like Copy in Finder.
- **Copy Path** — copies the paths of the dragged files, one per line.
- **AirDrop** — opens the AirDrop share sheet with the dragged files.
- **Compress** — like Compress in Finder: one item becomes `name.zip`, several become one
  `Archive.zip`.
- **Extract** — offered when every dragged file is an archive. Like Archive Utility: an archive
  holding a single item extracts to that item, otherwise to a folder named after the archive.

## Behaviour

- Output is written next to the original, same base name, new extension. On a name collision,
  Finder-style numbering: `name 2.png`, `name 3.png`, … Double extensions count as one:
  `name.tar.gz` becomes `name.zip`.
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
| Subtitles (SRT, VTT, TXT)                      | Own parser                                        |
| Office documents with their page layout        | Undecided; would need LibreOffice                 |
| Markdown output                                | Own writer from NSAttributedString                |
| Password-protected archives                    | Password prompt                                   |
| Move action                                    | Folder picker                                     |
| Float (a floating shelf of files)              | Own window                                        |
| Keyboard path (Enter on a Finder selection)    | Needs Finder selection access                     |

## Open questions

- Whether releases will be notarized. That needs a paid Apple Developer account; without it,
  users have to approve the app manually on first launch.
