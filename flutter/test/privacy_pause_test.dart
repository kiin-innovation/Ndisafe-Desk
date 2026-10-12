import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/privacy_pause.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget control(
          {bool paused = false,
          bool confirmed = true,
          required ValueChanged<bool> onChanged,
          double width = 260}) =>
      MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: width,
                    child: PrivacyPauseControl(
                        paused: paused,
                        confirmed: confirmed,
                        onChanged: onChanged,
                        pauseLabel: 'Pause sharing',
                        resumeLabel: 'Resume sharing',
                        pendingLabel: 'Waiting',
                        errorLabel:
                            'Privacy pause could not be confirmed. Do not enter confidential information.')))),
      );

  testWidgets('waits for host confirmation and prevents duplicate clicks',
      (tester) async {
    final requests = <bool>[];
    await tester.pumpWidget(control(onChanged: requests.add));
    await tester.tap(find.text('Pause sharing'));
    await tester.pump();
    expect(requests, [true]);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Resume sharing'), findsNothing);
    await tester.tap(find.text('Waiting'), warnIfMissed: false);
    expect(requests, [true]);
    await tester.pumpWidget(control(paused: true, onChanged: requests.add));
    expect(find.text('Resume sharing'), findsOneWidget);
    await tester.tap(find.text('Resume sharing'));
    expect(requests, [true, false]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('timeout warns instead of claiming sharing is paused',
      (tester) async {
    await tester.pumpWidget(control(onChanged: (_) {}));
    await tester.tap(find.text('Pause sharing'));
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Pause sharing'), findsOneWidget);
    expect(find.textContaining('Do not enter confidential information'),
        findsOneWidget);
    expect(find.text('Resume sharing'), findsNothing);
  });

  testWidgets('unconfirmed helper failure remains visible and permits resume',
      (tester) async {
    final requests = <bool>[];
    await tester.pumpWidget(control(
        paused: true, confirmed: false, onChanged: requests.add, width: 220));
    expect(find.textContaining('Do not enter confidential information'),
        findsOneWidget);
    await tester.tap(find.text('Resume sharing'));
    expect(requests, [false]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposal cancels the pending confirmation timeout',
      (tester) async {
    await tester.pumpWidget(control(onChanged: (_) {}));
    await tester.tap(find.text('Pause sharing'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opaque cover prevents pointer input reaching the screen',
      (tester) async {
    var clicks = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      Positioned.fill(
          child: GestureDetector(
              onTap: () => clicks++,
              child: const ColoredBox(color: Colors.red))),
      const Positioned.fill(child: PrivacyPauseCover(label: 'Sharing paused')),
    ]))));
    await tester.tapAt(const Offset(20, 20));
    expect(clicks, 0);
    expect(find.text('Sharing paused'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controls and cover fit a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(control(onChanged: (_) {}, width: 220));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox.expand(
                child: PrivacyPauseCover(label: 'Sharing paused')))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('translated privacy controls fit narrow windows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final labels in [
      [
        "Hagarika gusangiza by'agateganyo",
        'Komeza gusangiza',
        "Gusangiza byahagaritswe by'agateganyo",
        "Guhagarika gusangiza ntibyashoboye kwemezwa. Ntukandike amakuru y'ibanga."
      ],
      [
        'Suspendre le partage',
        'Reprendre le partage',
        'Partage suspendu',
        "La suspension du partage n'a pas pu être confirmée. Ne saisissez aucune information confidentielle."
      ],
    ]) {
      final requests = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
              body: Center(
                  child: SizedBox(
            width: 220,
            child: PrivacyPauseControl(
              paused: false,
              confirmed: false,
              onChanged: requests.add,
              pauseLabel: labels[0],
              resumeLabel: labels[1],
              pendingLabel: 'Waiting',
              errorLabel: labels[3],
            ),
          ))),
        ),
      ));
      expect(find.text(labels[3]), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(labels[0]));
      expect(requests, [true]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox.expand(
          child: PrivacyPauseCover(label: labels[2]),
        )),
      ));
      expect(find.text(labels[2]), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
