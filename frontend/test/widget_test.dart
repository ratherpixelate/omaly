import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('OmalyApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const OmalyApp());

    // Verify app starts up.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
