# Responsiveness and performance

NDISafe Desk has two separate performance budgets: local UI responsiveness and
remote-session latency. A responsive UI cannot remove propagation delay, relay
distance, insufficient bandwidth, or a peer's slow capture/decoder.

## Implementation map

| Area | Main code | Existing mechanism |
| --- | --- | --- |
| UI and input | `flutter/lib/models/input_model.dart` | Event-driven input and timer-based trackpad inertia |
| Connection routing | `src/client.rs` | Direct connections, UDP hole punching, relay fallback |
| Transport | `libs/hbb_common/src/tcp.rs`, `proxy.rs` | TCP_NODELAY on direct and proxied streams |
| Capture and pacing | `src/server/video_service.rs` | Capture interval follows adaptive FPS |
| Network adaptation | `src/server/video_qos.rs` | Per-viewer RTT estimation, FPS and bitrate adaptation |
| Software encoding | `libs/scrap/src/common/vpxcodec.rs`, `aom.rs` | Real-time encoding, multithreading |
| Decode backpressure | `src/client/io_loop.rs` | Decoder-capacity FPS limits and keyframe refresh on backlog |
| Rendering | `flutter/lib/models/model.dart` | Texture rendering where available, image fallback |

## Targeted fixes

- Trackpad cancellation no longer sleeps on the Dart UI isolate. Timer callbacks
  cannot run while that isolate is sleeping; cancellation is synchronous.
- Adaptive video subtracts estimated baseline RTT with saturating subtraction.
  Previously, a sample equal to or below the baseline was treated as its full
  measured delay. Stable distant connections could consequently stay at low FPS.
- The short delay history holds exactly two samples, not three, so old congestion
  samples expire at the intended rate.
- A received delay response clears the pending-response timeout flag immediately.
  Actual unanswered responses still cap FPS, and added queue delay still lowers
  FPS and quality.
- VP8/VP9 explicitly set `g_lag_in_frames = 0`, including after quality changes.
  This matches the encoder's low-latency contract. AOM already disables lookahead.
  The existing per-frame flush remains unchanged; this is not a claim that every
  previous session incurred the library's maximum lookahead delay.

The [libvpx encoder configuration documentation](https://chromium.googlesource.com/webm/libvpx/+/refs/heads/main/vpx/vpx_encoder.h)
describes zero lag as disabling future-frame lookahead.

Encoded delta frames must not be dropped arbitrarily: subsequent frames can
depend on them. Existing keyframe refresh and decoder feedback remain in place.
User-selected FPS, decoder-capacity limits, quality settings, and the shared
stream's slowest-viewer constraint remain respected.

## Automated checks

From the repository root:

```powershell
cargo test --offline --features flutter --lib video_qos::tests
cargo test --offline -p scrap --lib vpxcodec::tests
```

QoS tests cover stable RTTs from 40 to 800 ms, real congestion, recovery, timeout
clearing, bounded delay history, multiple viewers, and custom/decoder FPS limits.
Codec tests encode and decode consecutive VP8 and VP9 frames, including VP9 I444,
without waiting for future frames or flushing, and check quality changes retain
zero lookahead. These checks are deterministic regressions, not WAN benchmarks.

From `flutter/`, using the installed Flutter SDK:

```powershell
dart analyze lib/models/input_model.dart
flutter test --no-pub test/input_modifier_utils_test.dart test/terminal_mouse_handler_test.dart test/terminal_keyboard_utils_test.dart test/terminal_model_lifecycle_test.dart test/autocomplete_peer_merge_test.dart
```

The Flutter regressions cover neighboring input, terminal, and peer-list behavior;
they do not measure trackpad latency. Validate gesture cancellation interactively
as part of the release checks below.

## Release validation

Use release/profile builds for timing; debug-mode frame times are not production
measurements. Validate on both a modest PC and a faster PC, with one and multiple
monitors, and with texture rendering and the supported image fallback.

1. Open the app, navigate settings, type/search in the peer list, resize the
   window, and repeatedly scroll/start/stop trackpad gestures. Capture Flutter
   frame timings and CPU/memory. At 60 Hz the UI frame budget is about 16.7 ms;
   compare the 95th/99th percentile frame times and missed frames before/after.
2. Connect two PCs on a LAN, then over an actual remote connection. Record direct
   versus relay transport, negotiated codec, resolution, measured delay, bitrate,
   FPS, CPU/GPU load, connection time, and time to the first frame.
3. Exercise typing, dragging, scrolling, and moving windows. Record input-to-screen
   latency separately from local UI frame timing.
4. Introduce bandwidth limits, jitter, and packet loss on a test network. Verify
   FPS/quality reduce under load and recover when the load is removed, without
   corrupt frames, stuck input, or rapid quality oscillation.
5. Repeat with a distant peer. A stable high RTT should not permanently collapse
   FPS once the baseline is learned (at least ten delay samples). RTT itself is
   still real input-to-screen delay, not a delay eliminated by this change.
6. Verify file transfers, audio, reconnects, simultaneous viewers, and recording
   remain usable while a remote session is active.

For geographic performance, measure the relay path before changing infrastructure.
The packaged default currently points to a single rendezvous location; moving or
adding relay capacity is a deployment task, not a client-side tuning switch. This
change does not provision servers or change users' connection configuration.

Windows release CI currently builds the Flutter Rust core without `hwcodec`.
Hardware acceleration could reduce CPU on supported machines, but enabling it
requires separate driver, codec compatibility, dependency-packaging, and fallback
validation. It is deliberately not enabled by these narrow fixes.

No end-to-end speedup or zero-lag guarantee should be reported from unit tests
alone. Record the release-build baseline and measurements before making claims.
