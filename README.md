<div align="center">

<img src="Resources/AppIcon.png" width="128" height="128" alt="solfin app icon">

# solfin

**A power-user Jellyfin client for macOS that plays through external [mpv](https://mpv.io).**

Browse your Jellyfin library in a native SwiftUI app; playback is handed to a real mpv
process for maximum format/codec/subtitle support — no server-side transcoding, no
compromises.

</div>

---

## Why

The official Jellyfin desktop clients lean on server-side transcoding and an embedded
player with limited codec/container support. solfin streams the **original file** and lets
**mpv** — which plays virtually anything — handle it, while keeping Jellyfin's playback
state (resume points, watched status) in sync.

## Features

- **Native SwiftUI** browsing: Login → Home (Continue Watching, Next Up, library shelves)
  → library grid → item / series detail, with async-cached poster & backdrop art.
- **Series → seasons → episodes** navigation with queue-based playback: starting an
  episode queues that episode and the following episodes, with next-episode autoplay on
  natural end (never on manual quit).
- **Direct play only** — requests the static original file (`?static=true`); no transcode
  negotiation.
- **Progress sync** — reports `Sessions/Playing` / `Progress` / `Stopped`; honours and
  saves resume points; marks items watched. Exactly one "stopped" report on every exit
  path.
- **Bespoke pointer-first OSC** (`scripts/solfin-osc.lua`) — a web/VLC-style controller
  built for solfin: gradient scrims, chapter markers, buffered range, hover **thumbnail
  previews** (via bundled [thumbfast](https://github.com/po5/thumbfast)), audio/subtitle
  track menus, a prominent **playback-speed** control (1.5× a tap away), volume slider, and
  a top title bar — tuned to Solfin's solar orange accent and tiny sun seek-handle motif in the **Inter** UI font. Real media titles
  shown via `--force-media-title`.
- **External mpv, isolated config** — solfin runs mpv with its own `--config-dir`, so your
  personal `~/.config/mpv` is never touched.
- Launches **fullscreen**; a **Now Playing** strip in the app reflects live playback state.

## Architecture

Generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` into
four targets:

| Target | Kind | Role |
|---|---|---|
| `JellyfinKit` | static lib | Async `URLSession` REST client + `Codable` models: auth (MediaBrowser header + Keychain), browsing, `PlaybackInfo`, direct-stream URLs, progress reporting, seasons/episodes. No third-party deps. |
| `PlaybackEngine` | static lib | Launches external mpv (`MPVProcess`), drives it over JSON IPC (`MPVIPC`), and orchestrates playback (`PlaybackController`) — resume, progress timer, exactly-once stop, and queue-based episode transitions. |
| `solfin` | macOS app | SwiftUI UI, `AppState`, `NowPlaying`, and the bundled `Resources/mpv` config + app icon. |
| `solfin-probe` | CLI tool | Headless harness to exercise the stack against a real server (`info`/`login`/`browse`/`plan`/`play`/`seasons`/`episodes`/`next`). |

**Playback flow:** `POST /Items/{id}/PlaybackInfo` → pick a direct-play source → build
`…/Videos/{id}/stream?static=true&mediaSourceId=…&api_key=…` → spawn mpv with our
config-dir + a per-play IPC socket at the resume position → report `Sessions/Playing`,
observe `time-pos`/`pause`, post `Progress` ~every 10 s, and `Stopped` on end/quit.
Queued episode transitions reuse the same mpv process and call `loadfile` only when the
next item is selected or reached naturally.

## Requirements

- macOS 14+, Xcode 26 / Swift 6.x toolchain.
- **mpv** on the system: `brew install mpv` (solfin looks in `/opt/homebrew/bin`,
  `/usr/local/bin`, then `PATH`).
- **XcodeGen** to (re)generate the project: `brew install xcodegen`.

## Build & run

```sh
xcodegen generate                 # regenerate solfin.xcodeproj from project.yml
open solfin.xcodeproj             # …or build from the CLI:
xcodebuild -scheme solfin -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/solfin-*/Build/Products/Debug/Solfin.app
```

In the app: sign in (server URL, username, password), pick a title, hit **Play**.

## Testing

Unit tests (no network — `URLProtocol`-mocked):

```sh
xcodebuild test -scheme solfin -destination 'platform=macOS'
```

Live end-to-end checks via the probe (reads `SOLFIN_SERVER` / `SOLFIN_USER` /
`SOLFIN_PASS`):

```sh
PROBE=$(find ~/Library/Developer/Xcode/DerivedData/solfin-*/Build/Products/Debug -name solfin-probe)
SOLFIN_USER=you SOLFIN_PASS=secret "$PROBE" browse
SOLFIN_USER=you SOLFIN_PASS=secret "$PROBE" play <itemId>
```

## Configuration

- **mpv config** lives in `Resources/mpv/` (bundled into the app and passed via
  `--config-dir`): `mpv.conf`, `input.conf`, the bespoke OSC (`scripts/solfin-osc.lua` +
  `script-opts/solfin-osc.conf`), the thumbnail engine (`scripts/thumbfast.lua` +
  `script-opts/thumbfast.conf`), and the `fonts/Inter.ttf` UI font. Edit these to change
  OSD look, scalers, cache, subtitle styling, or key bindings; rebuild to re-bundle.
- **mpv binary path** can be overridden (`solfin.mpvPath` in `UserDefaults`); no Settings
  UI yet.

## Project layout

```
solfin/
├─ project.yml                 XcodeGen spec
├─ Sources/{JellyfinKit,PlaybackEngine,App,Probe}/
├─ Tests/                      XCTest suites
├─ Resources/mpv/              mpv.conf, input.conf, solfin-osc + thumbfast + Inter
├─ Resources/Assets.xcassets/  AppIcon
└─ docs/PLAN.md                design doc + as-built deviations
```

## Known limitations / not yet done

- Direct-play only — no transcoding, so very high-bitrate files need adequate bandwidth.
- Single server; limited keyboard navigation and no library search yet.
  mpv is used from Homebrew (not bundled/notarized).
- See `docs/PLAN.md` → *As-built deviations* for the full record.

## Development disclosure

This project is developed with AI assistance. Human maintainers review, test, and are
responsible for all changes before they are merged or released.

## Acknowledgements

solfin stands on excellent open-source work:

- **[mpv](https://mpv.io)** — the media player that does the actual playback (run as an
  external process). GPLv2+/LGPL.
- **[Jellyfin](https://jellyfin.org)** — the free software media server and its REST API.
- **[thumbfast](https://github.com/po5/thumbfast)** by po5 — the on-the-fly thumbnail
  engine the OSC uses for seek previews (MPL-2.0). The `solfin-osc.lua` controller itself is
  original to solfin, in the lineage of mpv's `osc.lua` (LGPLv2.1).
- **[Inter](https://rsms.me/inter/)** by Rasmus Andersson — the bundled UI font (SIL OFL-1.1;
  full text in `Resources/mpv/fonts/Inter-OFL.txt`).
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** by Yonas Kolb — project generation.

Please consult each project's license for terms. solfin ships mpv config scripts
(`solfin-osc.lua`, `thumbfast.lua`) and the Inter font inside its app bundle; it does not
link mpv (it spawns the binary).

## License

Not yet specified. The solfin source is provided as-is; bundled third-party assets
(thumbfast — MPL-2.0; Inter — OFL-1.1) retain their upstream licenses.
