import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NDISafe logo assets render their brand colors', (tester) async {
    for (final asset in ['assets/logo.svg', 'assets/icon.svg']) {
      final source = await rootBundle.loadString(asset);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 256,
              height: 256,
              child: SvgPicture.string(source),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      var greenPixels = 0;
      var bluePixels = 0;
      for (var i = 0; i < bytes!.length; i += 4) {
        if (bytes[i] == 78 && bytes[i + 1] == 183 && bytes[i + 2] == 155) {
          greenPixels++;
        }
        if (bytes[i] == 42 && bytes[i + 1] == 73 && bytes[i + 2] == 110) {
          bluePixels++;
        }
      }
      expect(greenPixels, greaterThan(1000), reason: asset);
      expect(bluePixels, greaterThan(1000), reason: asset);
      expect(tester.takeException(), isNull);
    }
  });
}
