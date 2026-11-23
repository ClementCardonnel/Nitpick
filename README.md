# Nitpick

Native macOS app that converts HDR content (Apple HDR stills and HDR video) to SDR
(8-bit BT.709), tone mapped the way macOS natively renders HDR on an SDR display.

See [ISSUE.md](ISSUE.md) for the full v1 spec.

## Architecture (RE:Flex, pillars 1–2)

```
Nitpick.xcodeproj   the macOS app target (signing, sandbox, icon, App Store archive)
Nitpick/            thin SwiftUI shell (sidebar queue, HDR|SDR previews, export bar)
├── AppIcon.icon        Icon Composer document (Liquid Glass app icon)
└── Assets.xcassets     AccentColor
Design/Icon/        generate-layers.swift: renders the icon's PNG layers
HDRCore/            local Swift package: the UI-free core (no AppKit/SwiftUI imports)
└── Sources/HDRCore/
    ├── AppState.swift / AppAction.swift   Elm-style state + actions
    ├── AppViewModel.swift                 single `update` reducer; effects fed back as actions
    └── Services/                          ToneMapper, MediaLoader, SDRExporter + live impls
```

- **Core:** `HDRCore` is a local Swift package the app target depends on;
  platform capabilities (folder picker) are injected via `CoreServices`.
- **App target:** App Sandbox with user-selected file read/write (dropped files
  and the chosen export folder), hardened runtime, generated Info.plist
  (Photography category). Set your team under Signing & Capabilities.
- **Tone mapping:** `CISystemToneMap` (the system tone curve) targeting SDR
  (display headroom 1.0, standard dynamic range), driven by the image's
  `contentHeadroom`; headroom is estimated from the brightest pixel when the
  source lacks metadata.
- **Stills:** ImageIO decode (`kCGImageSourceDecodeToHDR`) → tone map → 8-bit
  HEIC/JPEG/PNG matching the source family, in the source's SDR gamut (e.g.
  Display P3), at maximum quality, with the source metadata copied.
- **Video:** AVAssetReader (half-float HDR frames) → per-frame tone map →
  AVAssetWriter in the source's codec (HEVC/H.264/ProRes), bitrate and
  container, tagged BT.709, with metadata copied and audio passed through.

## Build & run

Open `Nitpick.xcodeproj` in Xcode and run the **Nitpick** scheme (macOS 26+,
Swift 6). From the command line:

```sh
xcodebuild -project Nitpick.xcodeproj -scheme Nitpick build
swift build --package-path HDRCore    # the core alone
```

## Usage

Drag & drop HDR files onto the window. Select a file to see the HDR source (left)
and the SDR result (right). **Export SDR…** picks a folder and exports the whole
queue as `Name_SDR.ext` (never overwriting; numeric suffix on collision), with
progress and cancel. Failed files show an inline error and are skipped at export.

## App icon

`Nitpick/AppIcon.icon` is an Icon Composer document: a flat background, two
glass half-suns (HDR and SDR) and an additive corona. Open it in Icon Composer
to tweak glass, shadows or appearances. To redraw the layer artwork:

```sh
swift Design/Icon/generate-layers.swift Nitpick/AppIcon.icon/Assets
```

