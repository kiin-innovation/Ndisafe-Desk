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
