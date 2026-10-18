# ffmpeg integration

Research notes for adding audio and video formats that AVFoundation can't handle. Nothing here
is built yet; the decisions taken are listed at the end.

## Approach

Bundle an LGPL ffmpeg **command-line binary**, built from source by a pinned script: static,
with a reduced set of encoders and muxers. Run it with `Process` from a new `FFmpegConverter`
registered **last**, so the registry's first-match rule keeps AVFoundation in charge of every
pair it already handles and ffmpeg only takes the rest.

Why the CLI rather than the alternatives:

- **CLI via `Process`** — a crash or hang stays in the child process, cancellation is
  `terminate()`, progress comes from `-progress pipe:1`, and the interface is ffmpeg's stable
  documented CLI. Roughly 200 lines of Swift.
- **Linking libav\*** — means hand-writing the decode → filter → encode → mux pipeline
  including timestamp handling; a crash takes down the menu-bar app; LGPL requires dynamic
  linking ([ffmpeg legal](https://ffmpeg.org/legal.html)). SwiftPM can't build ffmpeg, and
  `xcodebuild -create-xcframework` needs Xcode, which this project doesn't use.
- **Wrappers** — ffmpeg-kit is retired and its binaries were removed
  ([README](https://cdn.jsdelivr.net/gh/arthenica/ffmpeg-kit@main/README.md));
  [SwiftFFmpeg](https://github.com/sunlubo/SwiftFFmpeg) is unstable bindings that still need
  the libraries; kingslay/FFmpegKit is reportedly GPL with a paid LGPL tier (unverified).

## Obtaining the binary

- **Homebrew is not relocatable**: `/opt/homebrew/bin/ffmpeg` links 19 dylibs under
  `/opt/homebrew`, and its build lacks libvorbis.
- **Prebuilt builds don't fit**: [evermeet.cx](https://evermeet.cx/ffmpeg/) is Intel-only and
  GPL; [BtbN](https://github.com/BtbN/FFmpeg-Builds) has no macOS builds;
  [osxexperts](https://www.osxexperts.net/) is GPL; [martin-riedl.de](https://ffmpeg.martin-riedl.de/)
  is arm64 + x86_64 and notarized but includes x264/x265 (GPL). Its published build script is a
  useful reference.
- **Build from source** with Command Line Tools clang. First build static libogg, libvorbis,
  libopus, LAME and libvpx into a dependency prefix, then:

```sh
./configure --prefix="$OUT" --cc=clang --arch=arm64 \
  --extra-cflags=-mmacosx-version-min=14.0 --extra-ldflags=-mmacosx-version-min=14.0 \
  --pkg-config-flags=--static --enable-static --disable-shared \
  --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib \
  --disable-ffplay --disable-ffprobe --disable-doc --disable-debug --disable-network --disable-avdevice \
  --enable-libmp3lame --enable-libopus --enable-libvorbis --enable-libvpx \
  --disable-encoders --enable-encoder=h264_videotoolbox,hevc_videotoolbox,aac_at,aac,libmp3lame,libopus,libvorbis,libvpx_vp9,flac,pcm_s16le,pcm_s16be,wmv2,wmav2,mpeg4,gif \
  --disable-muxers --enable-muxer=mp4,mov,ipod,matroska,webm,avi,asf,gif,mp3,ogg,oga,opus,flac,wav,aiff \
  --disable-protocols --enable-protocol=file,pipe
```

Decoders, demuxers, parsers and filters stay at their defaults so any input ffmpeg can read is
accepted; trimming filters risks breaking ones ffmpeg inserts automatically.

Only arm64 is built (see Decisions).

## Licensing

Every target format works under LGPL: H.264/HEVC via VideoToolbox, MP3 via LAME (LGPL), and
Opus, Vorbis and VP9 are BSD. GPL would only add x264/x265, which give better quality per bit
than VideoToolbox.

Calling ffmpeg through `Process` counts as separate programs
([GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html#MereAggregation)), so Clementine's own
license is free either way. Each release must still ship the license texts, the exact source
tarballs of ffmpeg and its dependencies plus the build script, and credit ffmpeg in the About box.

## Bundling and signing

- Place the binary at `Contents/MacOS/ffmpeg` — Apple's location for helper tools
  ([Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)) —
  and find it with `Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")`.
- Sign inside-out, never `--deep`: first
  `codesign -f -s "Developer ID Application: …" -o runtime --timestamp -i <bundle-id>.ffmpeg Contents/MacOS/ffmpeg`,
  then the app. Notarization rejects executables without hardened runtime or a secure timestamp
  ([Resolving notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)).
- No entitlements: no JIT, no dylibs.
- Unverified: whether a user's first-launch approval of a non-notarized app also covers the
  nested helper.

## Runtime

- Invocation:
  `ffmpeg -nostdin -hide_banner -nostats -y -i SRC … -progress pipe:1 -stats_period 0.5 -f <muxer> DEST`.
  `-f` must be explicit: the runner's temp filename doesn't pick the right muxer for every
  format (M4A needs `ipod`, Opus needs `opus`).
- Progress: stdout emits `key=value` blocks ending in `progress=continue` / `progress=end`; use
  `out_time_us`. Duration comes from the `Duration: HH:MM:SS.xx` line ffmpeg prints on stderr,
  so ffprobe isn't needed.
- Read stdout and stderr concurrently, or a full pipe buffer deadlocks the process.
- Cancellation: `withTaskCancellationHandler { process.terminate() }`. On SIGTERM ffmpeg exits
  255 and finalizes a partial file; the runner's temp folder already discards it.
- Errors: any non-zero exit is a failure (missing input 254, invalid input 183). Map
  "Invalid data found when processing input" to `.unreadableSource` and
  "does not contain any stream" to `.noAudioTrack`; otherwise surface the last stderr line.
- No hard timeout, since long files are legitimate; at most a stall watchdog when no progress
  arrives for ~60 s.
- The `Converter` protocol has no progress channel yet.

## Formats and defaults

| Output | Encoders and settings |
|--------|-----------------------|
| MKV    | `-c copy` from MP4/MOV; otherwise `h264_videotoolbox -q:v 65` + `aac_at` |
| WebM   | `libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 -cpu-used 4` + `libopus 128k` (values unverified) |
| AVI    | `mpeg4 -q:v 3 -tag:v xvid` + `libmp3lame -q:a 2` |
| WMV    | `wmv2 -q:v 3` + `wmav2 192k` |
| GIF    | `fps=15,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse` |
| MP3    | `libmp3lame -q:a 2` |
| OGG    | `libvorbis -q:a 5` (not tested locally) |
| Opus   | `libopus 128k` — the native opus/vorbis encoders are experimental |
| WMA    | `wmav2 192k` |
| MP4, MOV, M4A, WAV, AIFF | only for inputs AVFoundation can't read: VideoToolbox + `aac_at`, or PCM |

`-q:v` constant quality with VideoToolbox is Apple-silicon only
([commit](https://ffmpeg.org/pipermail/ffmpeg-cvslog/2021-March/126704.html)); Intel needs `-b:v`.

Settings other than OGG were tested against a local ffmpeg 9.0.1.

## File types

- `.mkv` has no system UTType (it resolves to a dynamic type conforming to neither `.movie` nor
  `.audio`), so `Info.plist` needs a `UTImportedTypeDeclarations` entry for it.
- `.opus` resolves to `org.xiph.ogg-audio`, the same type as `.ogg`, so under the
  never-convert-to-itself rule OGG and Opus would never be offered to each other unless Opus is
  declared as its own type.
- Checked on macOS 27 only; resolution may differ on macOS 14.

## Size

About 15–20 MB on arm64, roughly halved when zipped. Estimated, not measured.

## Decisions

- **Apple silicon only.** No x86_64 build, so `-q:v` constant quality with VideoToolbox is
  always available.
- **ffmpeg is the fallback.** It handles every pair AVFoundation doesn't, and it is retried
  when AVFoundation accepts a file but then fails to convert it (e.g. VP9 inside MP4).
- **Progress only for long conversions**, shown from the menu bar so the user can follow them.
  Short conversions show nothing. This needs a progress channel on the `Converter` protocol.
- **FLAC output stays with AVFoundation.** Core Audio encodes FLAC natively (a 60 s stereo file
  in 0.26 s, read back as 24-bit FLAC); quality is identical because FLAC is lossless, and it
  works without ffmpeg.
- **LGPL build with VideoToolbox**, no x264/x265.
- **VP9 for WebM**: it plays almost everywhere and encodes far faster than SVT-AV1 in
  software.
- **Clementine is MIT-licensed.** Calling ffmpeg as a separate program leaves that unaffected;
  releases still carry ffmpeg's license texts and sources as described under Licensing.
