# Thumbfast-only previews

Solfin uses its patched thumbfast worker for every seek preview. No Jellyfin
Trickplay metadata request, endpoint, or pre-generated image dependency remains.
The worker starts shortly after mpv loads the playback file, then stays warm for
seekbar hovers. This removes most first-hover process/open cost at the expense
of a second active stream and decoder during playback.

## Solfin implementation

- `solfin-osc.lua` asks thumbfast for a frame and positions its raw overlay next
  to the seekbar. It consumes the worker's dimensions and scales for Retina.
- The fork opens a second direct-play connection after `file-loaded`. It decodes
  the start position to warm the worker; each later seek decodes a nearby keyframe
  into a small BGRA image, possibly requiring another HTTP range. Hover avoids
  worker/process/connection startup, but still waits for random seek/decode.
- Thumbnail failures and retry exhaustion never interrupt primary playback.

## Thumbfast fork maintenance

`Resources/mpv/scripts/thumbfast.lua` is a **Solfin-maintained fork** of
[po5/thumbfast](https://github.com/po5/thumbfast), derived from the repository's
vendored copy at `ff5563a` (the original upstream revision was not recorded).
The MPL-2.0 license notice and attribution are retained. Its file header explicitly
marks the fork; do not replace it with a stock upstream script without porting:

- macOS Lua mailbox bridge (`script-modules/thumbfast-worker.lua`) replacing
  shell/chmod/tail races and buffering; complete-line reads and latest-seek wins.
- Correct macOS subprocess environment scoping and list format.
- Async worker handles, generation-specific files/callbacks and cleanup on
  resize, file change, inactivity, disable and shutdown.
- Crash/stall recovery: 20-second request watchdog, 10-second network timeout,
  retry backoff (1 s, 2 s), at most three consecutive failures until the next file.
- 150 ms seek coalescing, second-level HTTP quantization, no costly exact
  refinement for long network media, 4 MiB demuxer buffer.
- `solfin_managed=yes` gate: keep the worker disabled during media open and
  prevent `spawn_first` from racing the main player. Start it 250 ms after
  `file-loaded` with Solfin's current position, then let worker warm-up obtain
  the first valid frame before the user reaches the seekbar.
- Overlay id 44 keeps thumbfast's cleanup separate from OSC/logo overlays.

This is primarily a macOS fork; upstream legacy OS/frontend code is retained but
not covered by Solfin's integration tests. First-hover HTTP opening/decoding cost
remains for previews because each cold random seek opens/reads/decodes the media stream.

## Verification

```sh
luajit tools/test-mpv-controls.lua
python3 tools/test-mpv-thumbnails.py # macOS + mpv + ffmpeg; loopback HTTP video
xcodebuild -scheme solfin -configuration Debug -destination 'platform=macOS' test
```

The Lua regression test verifies maximize/restore and OSC-to-thumbfast messaging.
The integration test verifies startup prewarming before hover, loopback HTTP
preview rendering, crash/stall recovery, file changes, inactivity and cleanup.

Manual: play and resume network/local media; hover, scrub quickly, switch files,
enter/leave fullscreen, and verify thumbnail failure does not disrupt playback.
