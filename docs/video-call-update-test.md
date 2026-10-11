# Two-way video and update test (1.4.10)

## Release

The NDISafe build workflow does not increment versions on branch pushes. A
branch push produces artifacts; pushing `1.4.10` also publishes a stable GitHub
Release. The Windows installer assets are published as soon as the Windows job
succeeds, without waiting for macOS or Linux. The legacy upstream tag workflow
is skipped for this repository to avoid turning the release into a prerelease.

Keep an installed 1.4.9 client for the update test. A portable ZIP is not an
installed client and offers Download instead of the in-place Update button.
After the stable release is published, reopen the old app with update checks
enabled. Startup checks after one second; an already-open app checks every
24 hours. Installing/updating must preserve the device ID and saved settings.

## Two PCs

1. Update both Windows PCs to 1.4.10 and connect cameras to both.
2. Start Video call from the remote-session toolbar on PC A.
3. On PC B, approve camera access if requested, then accept the incoming call.
4. B opens a camera-only return session to A. Approve camera access on A using
   its existing authorization prompt (or its normal saved-password policy).
   No remote-control permissions or passwords are borrowed from the first
   session. Both PCs should now see the other camera and hear the other person.
5. End call from either camera toolbar. Both call camera windows should close
   and voice capture should stop. Repeat using B's connection-manager Stop
   voice call button and by closing either call camera window.
6. Reject a call, disconnect the caller during acceptance, and call again.
   There should be no orphan camera window or repeated audio invitation.
7. Open an unrelated camera view, then make and end a video call. Ending the
   call must not close the unrelated camera view.
8. Make a normal voice-only call. Accepting it must not open either camera.

The return camera window belongs to the accepting connection manager and
hangs up its incoming call when closed. It does not initiate another voice
request. Existing camera viewing and camera-only authorization are unchanged.
This implementation targets desktop receivers; Android incoming calls retain
their existing flow.

## Automated checks

`flutter test --no-pub test/video_call_test.dart` covers explicit camera-call
acceptance, voice-only calls, duplicate events, cancellation before/during
window creation, isolated calls, connection reuse, failure propagation, and
the one-shot audio request. The Windows build runs these tests before uploading
release artifacts. These are lifecycle tests, not a substitute for two-PC
camera/audio and installed-client update testing.
