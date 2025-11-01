import 'package:biometry_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Example app initial UI and validation smoke test',
      (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const BiometryApp());

    // Verify key elements of the initial UI are present.
    expect(
        find.text('Biometric Authentication'), findsOneWidget); // AppBar title
    expect(find.text('Initialize Session'), findsOneWidget); // Section header

    // Verify form fields by their labels.
    expect(find.widgetWithText(TextFormField, 'Token'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Full Name'), findsOneWidget);

    // Verify the primary initialize button exists.
    final initButton = find.text('Initialize Biometry');
    expect(initButton, findsOneWidget);

    // Tap initialize without inputs to trigger validation snackbar for token.
    await tester.tap(initButton);
    await tester.pumpAndSettle();

    // Expect the snackbar with the validation message.
    expect(find.text('Please enter a valid token.'), findsOneWidget);
  });
}
