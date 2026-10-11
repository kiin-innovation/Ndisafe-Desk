import 'dart:async';

import 'package:flutter_hbb/utils/video_call.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoCallCameras', () {
    late VideoCallCameras cameras;
    late List<String> events;

    setUp(() {
      events = [];
      cameras = VideoCallCameras(
        open: (id, peerId) async {
          events.add('open:$id:$peerId');
          return id;
        },
        close: (id) async => events.add('close:$id'),
      );
    });

    test('opens a return camera only after an explicitly accepted camera call',
        () async {
      await cameras.started(1, 'peer');
      cameras.accept(2, isCamera: false);
      await cameras.started(2, 'peer');
      cameras.accept(3, isCamera: true);
      await cameras.started(3, 'peer');
      expect(events, ['open:3:peer']);
    });

    test('duplicate start and close events are idempotent', () async {
      cameras.accept(1, isCamera: true);
      await cameras.started(1, 'peer');
      await cameras.started(1, 'peer');
      await cameras.ended(1);
      await cameras.ended(1);
      expect(events, ['open:1:peer', 'close:1']);
    });

    test('ending before start cancels the accepted call', () async {
      cameras.accept(1, isCamera: true);
      await cameras.ended(1);
      await cameras.started(1, 'peer');
      expect(events, isEmpty);
    });

    test('ending during window creation waits and closes that window',
        () async {
      final ready = Completer<int>();
      cameras = VideoCallCameras(
        open: (id, peerId) => ready.future,
        close: (id) async => events.add('close:$id'),
      );
      cameras.accept(1, isCamera: true);
      final starting = cameras.started(1, 'peer');
      final ending = cameras.ended(1);
      expect(events, isEmpty);
      ready.complete(42);
      await Future.wait([starting, ending]);
      expect(events, ['close:42']);
    });

    test('closing one call does not close another call', () async {
      cameras.accept(1, isCamera: true);
      cameras.accept(2, isCamera: true);
      await cameras.started(1, 'peer-a');
      await cameras.started(2, 'peer-b');
      await cameras.ended(1);
      expect(events, ['open:1:peer-a', 'open:2:peer-b', 'close:1']);
    });

    test('a new call can start on the same connection after hang-up', () async {
      cameras.accept(1, isCamera: true);
      await cameras.started(1, 'peer');
      await cameras.ended(1);
      cameras.accept(1, isCamera: true);
      await cameras.started(1, 'peer');
      expect(events, ['open:1:peer', 'close:1', 'open:1:peer']);
    });

    test('creation failures are surfaced and do not leave a tracked window',
        () async {
      cameras = VideoCallCameras(
        open: (id, peerId) async => throw StateError('camera unavailable'),
        close: (id) async => events.add('close:$id'),
      );
      cameras.accept(1, isCamera: true);
      await expectLater(cameras.started(1, 'peer'), throwsStateError);
      await cameras.ended(1);
      expect(events, isEmpty);
    });

    test('late hang-up closes only the old window when a connection is reused',
        () async {
      final ready = Completer<int>();
      var opens = 0;
      cameras = VideoCallCameras(
        open: (id, peerId) => ++opens == 1 ? ready.future : Future.value(43),
        close: (windowId) async => events.add('close:$windowId'),
      );
      cameras.accept(1, isCamera: true);
      final starting = cameras.started(1, 'peer');
      final ending = cameras.ended(1);
      cameras.accept(1, isCamera: true);
      await cameras.started(1, 'peer');
      ready.complete(42);
      await Future.wait([starting, ending]);
      expect(events, ['close:42']);
      await cameras.ended(1);
      expect(events, ['close:42', 'close:43']);
    });
  });

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
