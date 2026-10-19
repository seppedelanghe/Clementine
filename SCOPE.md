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
| Documents | DOCX                             | PDF, TXT                   | Bundled `docxide-pdf` |
| Documents | RTF, HTML, TXT                   | PDF, DOCX, RTF, HTML, TXT  | NSAttributedString, own DOCX writer |
| Documents | MD                               | PDF, DOCX, HTML, TXT       | Foundation's Markdown parser, own DOCX writer |
| Documents | PDF                              | DOCX, TXT                  | PDFKit, own DOCX writer |
| Documents | Pages                            | PDF, DOCX, RTF, TXT, EPUB  | Pages, only when installed |

Documents are only offered where the result is good. DOCX → PDF is laid out like Word prints it:
pages, headers and footers, images, text boxes and shapes, with Calibri and Cambria drawn in their
metric-compatible clones Carlito and Caladea. A DOCX that `docxide-pdf` can't render falls back to
a text-only PDF. DOCX output is written by Clementine itself, so tables, images, lists and code
blocks survive, which Cocoa's own DOCX writer drops. PDF → DOCX joins each page's lines back into
paragraphs; scanned PDFs have no text to extract. Pages files are exported by Pages itself, which
asks once for Automation permission.

Known quirks of DOCX → PDF:

- Cover pages built from page-anchored shapes and hidden content can come out split over extra
  pages: a test document Word prints on 8 pages came out on 10, with the cover title on the
  page after the cover image and a blank page after it.
- Arrows and connectors in shape diagrams can land slightly off their boxes.
- Aptos, Word's newer default font, has no free metric-compatible clone, so line breaks in Aptos
  documents can differ from Word's.

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
| DOC and ODT input; DOCX to anything but PDF/TXT | No engine keeps their layout under ~140 MB; LibreOffice as an optional download |
| Markdown output                                | Own writer from NSAttributedString                |
| OCR for scanned PDFs                           | Vision                                            |
| Password-protected archives                    | Password prompt                                   |
| Move action                                    | Folder picker                                     |
| Float (a floating shelf of files)              | Own window                                        |
| Keyboard path (Enter on a Finder selection)    | Needs Finder selection access                     |

## Open questions

- Whether releases will be notarized. That needs a paid Apple Developer account; without it,
  users have to approve the app manually on first launch.
