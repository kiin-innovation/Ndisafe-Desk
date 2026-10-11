/// One-shot gate for the video-call automatic voice dial.
///
/// The camera pages fire the dial from the first-image callback, which can
/// run again (reconnect, display switch). Without this gate the peer would
/// get rung twice. Pure logic, no platform calls, fully unit-testable.
class AutoVoiceCallGate {
  bool _sent = false;

  /// Returns true exactly once when [autoVoiceCall] is enabled, false
  /// otherwise (including every call after the first granted one).
  bool shouldRequestVoiceCall(bool? autoVoiceCall) {
    if ((autoVoiceCall ?? false) && !_sent) {
      _sent = true;
      return true;
    }
    return false;
  }
}

/// Owns only the return-camera windows created by explicitly accepted calls.
class VideoCallCameras {
  final Future<int> Function(int, String) open;
  final Future<void> Function(int) close;
  final Set<int> _accepted = {};
  final Map<int, Future<int>> _opening = {};

  VideoCallCameras({required this.open, required this.close});

  void accept(int id, {required bool isCamera}) {
    if (isCamera) _accepted.add(id);
  }

  Future<void> started(int id, String peerId) async {
    if (!_accepted.remove(id) || _opening.containsKey(id)) return;
    final opening = Future<int>.sync(() => open(id, peerId));
    _opening[id] = opening;
    try {
      await opening;
    } catch (_) {
      if (identical(_opening[id], opening)) _opening.remove(id);
      rethrow;
    }
  }

  Future<void> ended(int id) async {
    _accepted.remove(id);
    final opening = _opening.remove(id);
    if (opening == null) return;
    // Window creation may still be in flight when the peer hangs up.
    final windowId = await opening;
    await close(windowId);
  }
}
