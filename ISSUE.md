# Nitpick — HDR → SDR converter for macOS (v1)

## Outcome

A greenfield, native macOS app (SwiftUI) that takes HDR content — Apple HDR stills and
HDR video — and exports it as SDR (8-bit BT.709), with the export tone-mapped the same
way macOS natively renders HDR content on an SDR display. The user drops files into the
app, sees the HDR source and the SDR result side by side, and exports the whole queue to
a folder with one click.

Reference architecture: Shopify's RE:Flex (https://shopify.engineering/reflex),
restricted to its first two pillars (see Boundaries).

## Flow / behavior

1. User drags & drops one or more files onto the window (File > Open also works).
2. Each file appears in a left sidebar list (thumbnail, name, status) and is loaded
   asynchronously: the Core decodes it and renders two static previews — HDR source
   (left pane) and SDR tone-mapped output (right pane). For video, the first frame is
   used for both previews; there is no inline playback in v1.
3. Selecting a file in the list shows its two previews in the center panes.
4. The Export button at the bottom opens a folder picker once, then exports **all**
   queued files into that folder, with an overall progress bar, the current file name,
   and a Cancel button (cancel stops after the current file; finished exports are kept).
5. When the run finishes, a summary lists succeeded and failed files. Failed files stay
   in the list with an inline error badge and are skipped during export.

## Requirements

- **Inputs:** Apple HDR stills (HEIC/HEIF 10-bit, gain-map HDR JPEG, ProPhoto RGB) and
  HDR video (HEVC/HLG, ProRes HDR in `.mov`). Files whose type is not a supported image
  or movie are rejected into an inline error state ("Unsupported format"); undecodable
  files get an inline error ("Could not decode …").
- **Previews:** two static stills per item. Left = HDR source as decoded (extended
  range preserved). Right = SDR render produced by the exact export pipeline
  (WYSIWYG). Video previews use the first frame.
- **Tone mapping:** default only in v1 — the export must match how a non-HDR macOS
  display renders the file natively (Apple's system tone mapping baked into the
  8-bit output). The tone mapping slider from the original idea is **deferred** to a
  follow-up; the `ToneMapper` protocol is the single seam where it will plug in.
- **Export format:** 8-bit SDR BT.709/sRGB. Stills keep their container family
  (HEIC → HEIC, JPEG → JPEG, PNG → PNG, other stills → HEIC). Video → H.264 `.mp4`
  with the **audio track preserved** (passthrough when possible).
- **Naming:** `SourceName_SDR.<ext>`; if the name exists in the target folder, append a
  numeric suffix (`SourceName_SDR 2.heic`). Never overwrite existing files.
- **Errors:** per-file inline error badges in the list; export skips failed files and
  reports them in the end-of-run summary.
- **Platform:** macOS 26+, Swift 6.4 (Swift 6 language mode). Local development only —
  no signing, sandbox, or notarization in this phase. Nothing persists between launches.

## Architecture (RE:Flex pillars 1–2)

- **`HDRCore` module (UI-free):** no AppKit/SwiftUI imports. All logic runs headlessly.
  Implemented as a local Swift package target; the app target depends on it.
- **Elm-style ViewModel:** `AppAction` in → `AppState` out → a single `update` function
  as the only place state changes. Side effects are returned as `AppEffect`s and executed
  by the view model, which sends follow-up actions (`loadFinished`, `exportProgress`,
  `exportFinished`) — keeping the reducer pure and testable.
- **Platform capabilities injected:** the Core is constructed with a `CoreServices`
  struct; the only UI-coupled capability is the export folder picker
  (`chooseExportFolder`), injected from the app target. Decoding, tone mapping, and
  export are real implementations inside the Core (ImageIO / CoreGraphics / CoreImage /
  AVFoundation — none are UI imports).
- **Deferred (explicitly out of v1):** RE:Flex pillars 3–4 — the JSON introspection
  contract per ViewModel and the CLI that drives it headlessly. The ViewModel shape is
  chosen so this can be added later as an extension without restructuring.

## Boundaries

- **In scope:** the flow above, for macOS 15+, unsigned local builds, manual QA only.
- **Out of scope / deferred:** tone mapping slider or any parameter UI; open formats
  (JPEG XL, EXR, 16-bit TIFF, AVIF…); introspection + CLI harness; automated tests;
  signing/sandbox/notarization/distribution; persistence of the queue; inline video
  playback or scrubbing; batch format picker (format is derived from input); overwrite
  behavior.
- **Tone mapping (verified during implementation):** a plain 8-bit `CGContext` draw
  *clamps* HDR highlights (confirmed by smoke test), so the implementation uses
  Core Image's `CISystemToneMap` filter — the system tone curve "consistent with
  other frameworks" — with `displayHeadroom = 1.0` and standard dynamic range,
  driven by the image's `contentHeadroom` (estimated from the brightest pixel when
  the source lacks metadata). Remaining manual check: compare against the native
  rendering of a real gain-map HEIC / HLG video on an SDR display.

## Acceptance criteria

- [ ] Dropping HDR stills (HEIC 10-bit, gain-map JPEG) and HDR video (.mov HEVC/HLG)
      shows each in the sidebar and renders both preview panes without errors.
- [ ] The right (SDR) pane matches what macOS natively shows for the same file on an
      SDR display, and matches the exported file pixel-for-pixel (same pipeline).
- [ ] Export writes every queued file to the chosen folder as `name_SDR.ext`
      (video → `.mp4`, audio preserved, 8-bit SDR BT.709), never overwriting existing
      files (numeric suffix instead).
- [ ] Progress bar, current-file label, and Cancel behave as specified; cancel keeps
      already-exported files.
- [ ] Unsupported or corrupt files show inline error badges, are skipped at export,
      and appear in the end-of-run summary.
- [ ] Rebuild from scratch (`swift build`) succeeds on macOS 15+ with no warnings that
      matter; the app runs from the package/Xcode and the full flow works manually.
- [ ] `HDRCore` contains no `import AppKit` / `import SwiftUI`.

## QA (manual, v1)

Fixture set: one HEIC 10-bit HDR still, one gain-map HDR JPEG, one ProPhoto TIFF,
one SDR JPEG (negative case), one corrupt file (negative case), one HEVC/HLG .mov
with audio, one ProRes HDR .mov. For each: drop, check previews, export, open the
result in Preview/QuickTime and compare against the system rendering on an SDR
display. Check naming/collision by exporting twice into the same folder.

## References

- RE:Flex architecture: https://shopify.engineering/reflex
- Workspace: `/Users/clementcardonnel/Developer/HDAuRevoir` (greenfield at planning time)
