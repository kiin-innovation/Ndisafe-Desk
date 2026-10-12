# Confidential-entry privacy pause

The person receiving desktop support uses Pause sharing in the local support
window. Wait for Resume sharing to appear without an error before entering
confidential information. Hide or close password fields and clear any sensitive
clipboard contents before resuming.
The session stays connected; chat and voice can continue.

The pause stops screen capture/recording and screen/cursor/clipboard delivery
to all viewers, and rejects remote input, screenshot requests, option changes,
file actions, and terminal actions. Queued video and input are discarded across
pause/resume. Updated viewers show Sharing paused; older viewers freeze on the
last pre-pause frame. No viewer can resume sharing through the network.

New connections are refused while paused. Existing auxiliary file,
terminal and port-forward sessions are closed rather than left able to access
the PC. Camera video freezes while keeping calls connected.
Already executing terminal commands cannot be undone; stop those
sessions before handling sensitive information. Windows elevated portable
input helpers must acknowledge the pause; failure shows a warning and does
not claim confidentiality is confirmed. When the last desktop viewer leaves,
pause state resets so the device does not become permanently inaccessible.

## Two-PC checks before release

1. Install the new host build and connect a supporter. Press Pause sharing
   locally; verify the host desktop stays usable and the supporter is covered.
2. Type test-only credentials, move the pointer, change clipboard content,
   request screenshots, and attempt mouse/keyboard input from the supporter.
   No new screen frames, clipboard data or input should pass during the pause.
3. Connect a second viewer before pausing. Both must stop; neither can resume.
   A new viewer attempting to connect during the pause must be rejected.
4. Hide credentials, then resume locally. The desktop must refresh promptly,
   with no replay of paused frames or keystrokes. Repeat rapidly and offline.
5. Repeat with a Windows elevated portable helper and with recording enabled.
   Inspect both recordings for absence of confidential-entry frames.
6. Disconnect one viewer while another remains: remain paused. Disconnect all
   viewers, then reconnect: do not leave a stuck pause state.
7. Test an old supporter: it must freeze without disclosure, even though it
   cannot display the new cover. Previously displayed/recorded data cannot
   be erased by this feature. Voice audio is not muted by the pause.

Native policy tests and Flutter widget tests cover gates, stale queues,
notifications, confirmation, error/timeout handling and responsive controls.
Full Windows helper/recording and cross-platform session checks remain manual.
