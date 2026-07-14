import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/vault/import_export/import_screen.dart';
import 'package:core/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Import Screen File Picker to Parser Mapping Tests', () {
    late List<int> vaultKey;
    late VaultDatabase db;

    setUp(() {
      vaultKey = List<int>.filled(32, 42);
      db = SqliteVaultDatabase.inMemory();
      db.open(vaultKey);
    });

    tearDown(() {
      db.close();
    });

    // Helper to navigate to file input step for a given format
    Future<void> navigateToFileInput(WidgetTester tester, String format) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImportScreen(vaultKey: vaultKey, db: db),
        ),
      );
      await tester.pumpAndSettle();

      // Find and tap the format card
      final formatCard = find.text(_formatDisplayName(format));
      expect(formatCard, findsOneWidget);
      await tester.tap(formatCard);
      await tester.pumpAndSettle();

      // Should be on file input step
      expect(find.text(_formatLabel(format)), findsOneWidget);
    }

    testWidgets('1. Bitwarden format selects BitwardenParser', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'bitwarden');

      // Paste valid Bitwarden JSON
      const jsonContent = '{"encrypted": false, "items": [{"type": 1, "name": "Test", "login": {"username": "u", "password": "p"}}]}';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, jsonContent);
      await tester.pumpAndSettle();

      // Tap Parse & Preview
      final parseButton = find.text('Parse & Preview');
      await tester.tap(parseButton);
      await tester.pumpAndSettle();

      // Should show preview with parsed items
      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Logins'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // 1 item
    });

    testWidgets('2. 1Password format selects OnePasswordParser', (WidgetTester tester) async {
      await navigateToFileInput(tester, '1password');

      const jsonContent = '{"accounts": [{"vaults": [{"items": [{"categoryUuid": "001", "overview": {"title": "Test"}, "details": {"loginFields": [{"designation": "username", "value": "u"}, {"designation": "password", "value": "p"}]}}]}]}]}]}';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, jsonContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Logins'), findsOneWidget);
    });

    testWidgets('3. LastPass format selects LastPassParser', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'lastpass');

      const csvContent = 'url,username,password,totp,extra,name,grouping,fav\nhttps://test.com,u,p,,notes,Test,Personal,1';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Logins'), findsOneWidget);
    });

    testWidgets('4. Chrome CSV preset uses GenericCsvParser with Chrome mapping', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'chrome_csv');

      const csvContent = 'name,url,username,password\nGoogle,https://google.com,chromeuser,chromepass';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Google'), findsOneWidget); // Title from 'name' column
    });

    testWidgets('5. Firefox CSV preset uses GenericCsvParser with Firefox mapping', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'firefox_csv');

      const csvContent = 'url,username,password\nhttps://firefox.com,firefoxuser,firefoxpass';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('https://firefox.com'), findsOneWidget); // Title from 'url' column
    });

    testWidgets('6. Safari CSV preset uses GenericCsvParser with Safari mapping', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'safari_csv');

      const csvContent = 'Title,URL,Username,Password,Notes,OTPAuth\nApple,https://apple.com,safariuser,safaripass,Safari notes,safaritotp';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Apple'), findsOneWidget);
    });

    testWidgets('7. Dashlane format selects DashlaneParser', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'dashlane');

      const csvContent = 'name,url,username,password,notes,otpsecret\nDashlane Item,https://dashlane.com,dashuser,dashpass,dashnotes,dashtotp';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Dashlane Item'), findsOneWidget);
    });

    testWidgets('8. Keeper format selects KeeperParser', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'keeper');

      const csvContent = 'Title,Login,Password,Website Address,Notes\nKeeper Item,keeperuser,keeperpass,https://keeper.com,keepernotes';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Keeper Item'), findsOneWidget);
    });

    testWidgets('9. NordPass format selects NordPassParser', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'nordpass');

      const csvContent = 'name,username,password,url,note\nNordPass Item,norduser,nordpass,https://nordpass.com,nordnotes';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('NordPass Item'), findsOneWidget);
    });

    testWidgets('10. RoboForm format selects RoboFormParser', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'roboform');

      const csvContent = 'name,login,pwd,url,note\nRoboForm Item,robouser,robopass,https://roboform.com,robonotes';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('RoboForm Item'), findsOneWidget);
    });

    testWidgets('11. Proton Pass format selects ProtonPassParser', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'protonpass');

      const jsonContent = '{"vaults": [{"name": "Personal", "items": [{"data": {"metadata": {"name": "Proton Item", "note": "protonnotes"}, "content": {"username": "protonuser", "password": "protonpass", "urls": ["https://proton.me"], "totpUri": "protontotp"}}}]}]}';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, jsonContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Proton Item'), findsOneWidget);
    });

    testWidgets('12. Generic CSV format uses GenericCsvParser with custom mapping', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'generic_csv');

      // Verify column mapping fields are shown
      expect(find.text('COLUMN MAPPING'), findsOneWidget);
      expect(find.text('Title column'), findsOneWidget);
      expect(find.text('Username column'), findsOneWidget);

      // Change column mapping
      await tester.enterText(find.widgetWithText(TextFormField, 'title'), 'site_name');
      await tester.pumpAndSettle();

      const csvContent = 'site_name,login_user,secret\nTest Site,testuser,testpass';
      final textField = find.byType(TextFormField).last; // Last text field is the file content
      await tester.enterText(textField, csvContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Import Preview'), findsOneWidget);
      expect(find.text('Test Site'), findsOneWidget);
    });

    testWidgets('13. KeePass KDBX format shows password/key file inputs', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'keepass_kdbx');

      // Verify KeePass-specific UI is shown
      expect(find.text('KEEPASS DECRYPTION CREDENTIALS'), findsOneWidget);
      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Key File Content'), findsOneWidget);
      expect(find.text('KDBX FILE CONTENT (BASE64)'), findsOneWidget);
    });

    testWidgets('14. All 13 format options are displayed in format picker', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImportScreen(vaultKey: vaultKey, db: db),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all format names are shown
      const expectedFormats = [
        'Bitwarden',
        '1Password',
        'LastPass',
        'Chrome Preset',
        'Firefox Preset',
        'Safari Preset',
        'Dashlane',
        'Keeper',
        'NordPass',
        'RoboForm',
        'Proton Pass',
        'KeePass (.kdbx)',
        'Generic CSV',
      ];

      for (final format in expectedFormats) {
        expect(find.text(format), findsOneWidget);
      }
    });

    testWidgets('15. Format picker shows clear file type labels', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImportScreen(vaultKey: vaultKey, db: db),
        ),
      );
      await tester.pumpAndSettle();

      // Verify each format has a descriptive subtitle
      expect(find.text('JSON export from Bitwarden'), findsOneWidget);
      expect(find.text('export.data from .1pux archive'), findsOneWidget);
      expect(find.text('CSV export from LastPass'), findsOneWidget);
      expect(find.text('CSV export from Google Chrome'), findsOneWidget);
      expect(find.text('CSV export from Mozilla Firefox'), findsOneWidget);
      expect(find.text('CSV export from Apple Safari'), findsOneWidget);
      expect(find.text('CSV export from Dashlane'), findsOneWidget);
      expect(find.text('CSV export from Keeper'), findsOneWidget);
      expect(find.text('CSV export from NordPass'), findsOneWidget);
      expect(find.text('CSV export from RoboForm'), findsOneWidget);
      expect(find.text('JSON export from Proton Pass'), findsOneWidget);
      expect(find.text('Encrypted KeePass database file'), findsOneWidget);
      expect(find.text('Any CSV with custom column mapping'), findsOneWidget);
    });

    testWidgets('16. Preview step shows item counts by type', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'bitwarden');

      const jsonContent = '{"encrypted": false, "items": [{"type": 1, "name": "Login1", "login": {"username": "u", "password": "p"}}, {"type": 2, "name": "Note1", "notes": "note"}]}';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, jsonContent);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('ITEMS TO IMPORT'), findsOneWidget);
      expect(find.text('Logins'), findsOneWidget);
      expect(find.text('Secure Notes'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2)); // 2 items total, plus count in "Total"
    });

    testWidgets('17. Preview step shows parse errors', (WidgetTester tester) async {
      await navigateToFileInput(tester, 'bitwarden');

      const invalidJson = '{invalid json}';
      final textField = find.byType(TextFormField).first;
      await tester.enterText(textField, invalidJson);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parse & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('PARSE WARNINGS / ERRORS'), findsOneWidget);
    });
  });
}

String _formatDisplayName(String format) {
  switch (format) {
    case 'bitwarden': return 'Bitwarden';
    case '1password': return '1Password';
    case 'lastpass': return 'LastPass';
    case 'chrome_csv': return 'Chrome Preset';
    case 'firefox_csv': return 'Firefox Preset';
    case 'safari_csv': return 'Safari Preset';
    case 'dashlane': return 'Dashlane';
    case 'keeper': return 'Keeper';
    case 'nordpass': return 'NordPass';
    case 'roboform': return 'RoboForm';
    case 'protonpass': return 'Proton Pass';
    case 'keepass_kdbx': return 'KeePass (.kdbx)';
    case 'generic_csv': return 'Generic CSV';
    default: return format;
  }
}

String _formatLabel(String format) {
  switch (format) {
    case 'bitwarden': return 'Bitwarden Import';
    case '1password': return '1Password Import';
    case 'lastpass': return 'LastPass Import';
    case 'chrome_csv': return 'Chrome CSV Import';
    case 'firefox_csv': return 'Firefox CSV Import';
    case 'safari_csv': return 'Safari CSV Import';
    case 'dashlane': return 'Dashlane CSV Import';
    case 'keeper': return 'Keeper CSV Import';
    case 'nordpass': return 'NordPass CSV Import';
    case 'roboform': return 'RoboForm CSV Import';
    case 'protonpass': return 'Proton Pass JSON Import';
    case 'keepass_kdbx': return 'KeePass (.kdbx) Import';
    case 'generic_csv': return 'Generic CSV Import';
    default: return 'Import';
  }
}
