import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('Password Strength Meter UI Interaction Test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(home: VaultHomeScreen()));

    // Verify initial home screen has the floating action button.
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // 1. Tap the '+' FAB to open the Type Picker.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Verify type picker is displayed.
    expect(find.text('Select Item Type'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);

    // 2. Select the 'Login' type to open the Editor form.
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    // Verify the Login Editor form is displayed.
    expect(find.byKey(const Key('password-field')), findsOneWidget);
    expect(find.text('No Password Entered'), findsOneWidget);

    // 3. Enter a weak password: '123456'
    await tester.enterText(find.byKey(const Key('password-field')), '123456');
    await tester.pump();

    // Verify strength is evaluated as Very Weak.
    expect(find.text('Strength: Very Weak'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsAtLeastNWidgets(1));

    // 4. Enter a strong password: 'correcthorsebatterystaple'
    await tester.enterText(find.byKey(const Key('password-field')), 'correcthorsebatterystaple');
    await tester.pump();

    // Verify strength is evaluated as Very Strong.
    expect(find.text('Strength: Very Strong'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('URL Scanner Tab UI Test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(home: VaultHomeScreen()));

    // 1. Switch to Security Center tab
    await tester.tap(find.text('Security Center'));
    await tester.pumpAndSettle();

    // 2. Tap on Phishing URL Scanner to open the screen
    await tester.ensureVisible(find.text('Phishing URL Scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phishing URL Scanner'));
    await tester.pumpAndSettle();

    // Verify URL Scanner screen content is displayed
    expect(find.text('Link & Phishing Protection'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // 3. Enter a homoglyph URL
    await tester.enterText(find.byType(TextField), 'https://\u0430pple.com');
    await tester.pump();

    // Verify live heuristic warning label is visible
    expect(find.text('Live Heuristic Scanner:'), findsOneWidget);
    expect(find.text('Homoglyph/Punycode'), findsOneWidget);

    // 4. Tap Scan URL
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5)); // Wait for timer timeouts

    // Verify scan results card is displayed
    expect(find.text('Malicious Activity Detected'), findsOneWidget);
  });

  testWidgets('Email Scanner Tab UI Test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(home: VaultHomeScreen()));

    // 1. Switch to Security Center tab
    await tester.tap(find.text('Security Center'));
    await tester.pumpAndSettle();

    // 2. Tap on Phishing Email Shield to open the screen
    await tester.ensureVisible(find.text('Phishing Email Shield'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phishing Email Shield'));
    await tester.pumpAndSettle();

    // Verify Email Scanner tab is shown
    expect(find.text('Email Spoofing & Phishing Scan'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);


    // 3. Paste a malicious raw email header
    final maliciousEmailSource = 'From: "PayPal Security" <support@scam-support.net>\n'
        'Authentication-Results: mx.google.com; spf=fail; dkim=fail; dmarc=fail\n\n'
        'Verify immediately! Your account is suspended.';

    await tester.enterText(find.byType(TextField), maliciousEmailSource);
    await tester.pump();

    // 4. Tap Scan button
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    // Verify results card shows suspicious indicator triggers
    expect(find.text('Suspicious Indicators Found'), findsOneWidget);
    expect(find.text('Sender: support@scam-support.net'), findsOneWidget);
    expect(find.text('Sender Spoofing Mismatch'), findsOneWidget);
    expect(find.text('FAIL'), findsAtLeastNWidgets(3)); // SPF, DKIM, DMARC fail
  });
}
