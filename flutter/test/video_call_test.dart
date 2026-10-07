import 'package:flutter_hbb/utils/video_call.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoVoiceCallGate', () {
    test('never dials a normal camera view (flag null)', () {
      final gate = AutoVoiceCallGate();
      expect(gate.shouldRequestVoiceCall(null), isFalse);
      expect(gate.shouldRequestVoiceCall(null), isFalse);
    });

    test('never dials a normal camera view (flag false)', () {
      final gate = AutoVoiceCallGate();
      expect(gate.shouldRequestVoiceCall(false), isFalse);
      expect(gate.shouldRequestVoiceCall(false), isFalse);
    });

    test('dials exactly once for a video call, even on repeat callbacks', () {
      final gate = AutoVoiceCallGate();
      // First image after connect: dial.
      expect(gate.shouldRequestVoiceCall(true), isTrue);
      // Reconnect / display switch / repeat callback: must not double-dial.
      expect(gate.shouldRequestVoiceCall(true), isFalse);
      expect(gate.shouldRequestVoiceCall(true), isFalse);
    });

    test('each camera page gets an independent gate', () {
      final first = AutoVoiceCallGate();
      final second = AutoVoiceCallGate();
      expect(first.shouldRequestVoiceCall(true), isTrue);
      // A second window/session still dials its own call once.
      expect(second.shouldRequestVoiceCall(true), isTrue);
      expect(first.shouldRequestVoiceCall(true), isFalse);
      expect(second.shouldRequestVoiceCall(true), isFalse);
    });
  });
}
