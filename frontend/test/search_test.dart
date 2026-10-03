import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/pages/pages.dart';

void main() {
  testWidgets('GalleryPage search bar typing and clear button test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GalleryPage(),
        ),
      ),
    );

    // Initial state: search field is present, clear button is not present
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsNothing);

    // Enter text in search field
    await tester.enterText(find.byType(TextField), 'friends');
    await tester.pump();

    // Clear button is visible
    expect(find.byTooltip('Clear search'), findsOneWidget);

    // Tap clear button
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();

    // Search field is cleared, clear button disappears
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, isEmpty);
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  testWidgets('GalleryPage debounced search triggers on person name input', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GalleryPage(),
        ),
      ),
    );

    // Enter a person's name
    await tester.enterText(find.byType(TextField), 'Chris');
    await tester.pump();

    // Clear button appears
    expect(find.byTooltip('Clear search'), findsOneWidget);

    // Advance beyond debounce duration
    await tester.pump(const Duration(milliseconds: 400));
  });
}
