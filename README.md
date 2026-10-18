<p align="center"><img src="assets/clementine.svg" width="96" alt="Clementine"></p>

# Clementine

Convert files on your Mac without opening an app. Start dragging a file, tap a key, drop it on a
wheel.

Everything runs locally. Files are never uploaded, and the original is never changed: the
converted file is saved next to it.

## How it works

1. Drag one or more files, from Finder or anywhere else.
2. While dragging, tap a key:
   - **Shift** opens the convert wheel.
   - **Control** opens the actions wheel.
3. Drop the files on a wedge.

Dropping anywhere else is a normal drop. Conversions that take longer than a couple of seconds
show their progress in the menu bar.

## What it converts

| From | To |
|------|----|
| Images: JPG, PNG, HEIC, TIFF, GIF, BMP, WebP | JPG, PNG, HEIC, TIFF, PDF |
| Video: MP4, MOV, MKV, WebM, AVI, WMV, … | MP4, MOV, MKV, WebM, AVI, WMV, GIF, M4A, MP3 |
| Audio: MP3, M4A, WAV, AIFF, FLAC, OGG, Opus, WMA, … | MP3, M4A, WAV, AIFF, FLAC, OGG, Opus, WMA |

Actions: **Copy Path** and **AirDrop**.

## Requirements

macOS 14 or later on Apple silicon.

## Building

Needs the Xcode Command Line Tools and `pkg-config` (`brew install pkgconf`). Xcode itself isn't
needed.

```sh
make run   # builds build/Clementine.app and opens it
```

The first build also downloads and compiles the bundled ffmpeg, which takes a few minutes.

## License

MIT, see [LICENSE](LICENSE). The bundled ffmpeg is built from source under the LGPL; see
[docs/ffmpeg.md](docs/ffmpeg.md).
