# HDAuRevoir

Native macOS app that converts HDR content (Apple HDR stills and HDR video) to SDR
(8-bit BT.709), tone mapped the way macOS natively renders HDR on an SDR display.

See [ISSUE.md](ISSUE.md) for the full v1 spec.

## Architecture (RE:Flex, pillars 1–2)

```
Sources/
├── HDRCore/        UI-free core (no AppKit/SwiftUI imports)
│   ├── AppState.swift / AppAction.swift   Elm-style state + actions
│   ├── AppViewModel.swift                 single `update` reducer; effects fed back as actions
│   └── Services/                          ToneMapper, MediaLoader, SDRExporter + live impls
└── HDAuRevoir/     thin SwiftUI shell (sidebar queue, HDR|SDR previews, export bar)
```

- **Core:** `HDRCore` is a plain Swift package target; platform capabilities
  (folder picker) are injected via `CoreServices`.
- **Tone mapping:** `CISystemToneMap` (the system tone curve) targeting SDR
  (display headroom 1.0, standard dynamic range), driven by the image's
  `contentHeadroom`; headroom is estimated from the brightest pixel when the
  source lacks metadata.
- **Stills:** ImageIO decode (`kCGImageSourceDecodeToHDR`) → tone map → 8-bit
  HEIC/JPEG/PNG matching the source family.
- **Video:** AVAssetReader (half-float HDR frames) → per-frame tone map →
  AVAssetWriter H.264 `.mp4`, audio passed through.

## Build & run

```sh
swift build
swift run HDAuRevoir    # macOS 26+, Swift 6
```

Or open `Package.swift` in Xcode for a full app experience.

## Usage

Drag & drop HDR files onto the window. Select a file to see the HDR source (left)
and the SDR result (right). **Export SDR…** picks a folder and exports the whole
queue as `Name_SDR.ext` (never overwriting; numeric suffix on collision), with
progress and cancel. Failed files show an inline error and are skipped at export.
