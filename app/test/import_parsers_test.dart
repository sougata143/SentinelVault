import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:kdbx/kdbx.dart';

/// Synthetic (non-real) fixture data for import parser tests.
/// None of these contain real credentials, keys, or personal data.

// ─── Bitwarden ───────────────────────────────────────────────────────────────
const _bitwardenJson = '''
{
  "encrypted": false,
  "items": [
    {
      "type": 1,
      "name": "Synthetic Login",
      "favorite": true,
      "notes": "Some login note",
      "login": {
        "username": "synth_user@example.com",
        "password": "SynthP@ssw0rd!",
        "totp": "SYNTH1234TOTP",
        "uris": [
          {"uri": "https://synthetic.example.com"}
        ]
      }
    },
    {
      "type": 2,
      "name": "Synthetic Note",
      "favorite": false,
      "notes": "This is a secure note body."
    },
    {
      "type": 3,
      "name": "Synthetic Card",
      "favorite": false,
      "notes": null,
      "card": {
        "cardholderName": "Test Cardholder",
        "number": "4111111111111111",
        "brand": "visa",
        "expMonth": "09",
        "expYear": "2030",
        "code": "123"
      }
    },
    {
      "type": 4,
      "name": "Synthetic Identity",
      "favorite": false,
      "notes": null,
      "identity": {
        "firstName": "Jane",
        "lastName": "Testsworth",
        "address1": "123 Test Street",
        "city": "Synthcity",
        "state": "TX",
        "postalCode": "10001",
        "country": "US"
      }
    },
    {
      "type": 99,
      "name": "Unknown Type Item",
      "favorite": false
    }
  ]
}
''';

// ─── 1Password ───────────────────────────────────────────────────────────────
const _onePasswordJson = '''
{
  "accounts": [
    {
      "vaults": [
        {
          "items": [
            {
              "categoryUuid": "001",
              "favIndex": 0,
              "overview": {
                "title": "Synthetic 1P Login",
                "urls": [
                  {"url": "https://1p.synthetic.example.com"}
                ]
              },
              "details": {
                "notes": "A 1Password note",
                "loginFields": [
                  {"designation": "username", "value": "user1p@example.com"},
                  {"designation": "password", "value": "1pSynthPass!"}
                ],
                "sections": []
              }
            },
            {
              "categoryUuid": "003",
              "favIndex": 0,
              "overview": {"title": "Synthetic 1P Note"},
              "details": {
                "notes": "Secret note content here.",
                "loginFields": [],
                "sections": []
              }
            },
            {
              "categoryUuid": "999",
              "favIndex": 0,
              "overview": {"title": "Unknown Category"},
              "details": {"loginFields": [], "sections": []}
            }
          ]
        }
      ]
    }
  ]
}
''';

// ─── LastPass ─────────────────────────────────────────────────────────────────
const _lastPassCsv = '''
url,username,password,totp,extra,name,grouping,fav
https://lp.example.com,lp_user@example.com,LpSynthPass!,LPTOTP123,"Some notes here",LP Synthetic Login,Personal,1
https://bank.example.com,bankuser,BankPass#1,,Bank login notes,LP Bank Login,Finance,0
,missingurl,NoURL123,,notes,LP No URL,Other,0
''';

// ─── Generic CSV ─────────────────────────────────────────────────────────────
const _genericCsv = '''
site_name,login_user,secret,link,description,unknown_col
Synthetic Site,gen_user@example.com,GenSynthPass!,https://generic.example.com,Generic notes,should_flag
Another Site,,EmptyUser123,https://another.example.com,Notes 2,also_flags
''';

void main() {
  group('Bitwarden Parser Tests', () {
    test('1. Parses 4 known items and flags unknown type as error', () {
      final result = BitwardenParser().parse(_bitwardenJson);

      // 4 known types should be parsed
      expect(result.items.length, equals(4));
      expect(result.errors.length, equals(1)); // type 99 is unknown

      // Login item
      final login = result.items[0];
      expect(login.type, equals('login'));
      expect(login.title, equals('Synthetic Login'));
      expect(login.username, equals('synth_user@example.com'));
      expect(login.password, equals('SynthP@ssw0rd!'));
      expect(login.totpSecret, equals('SYNTH1234TOTP'));
      expect(login.urls, contains('https://synthetic.example.com'));
      expect(login.notes, equals('Some login note'));
      expect(login.favorite, isTrue);

      // Secure note
      final note = result.items[1];
      expect(note.type, equals('secure_note'));
      expect(note.noteContent, equals('This is a secure note body.'));

      // Credit card
      final card = result.items[2];
      expect(card.type, equals('credit_card'));
      expect(card.cardholderName, equals('Test Cardholder'));
      expect(card.cardNumber, equals('4111111111111111'));
      expect(card.cardBrand, equals('visa'));
      expect(card.cardExpiryMonth, equals(9));
      expect(card.cardExpiryYear, equals(2030));
      expect(card.cardCvv, equals('123'));

      // Identity
      final id = result.items[3];
      expect(id.type, equals('identity'));
      expect(id.firstName, equals('Jane'));
      expect(id.lastName, equals('Testsworth'));
      expect(id.street, equals('123 Test Street'));
      expect(id.city, equals('Synthcity'));

      // Error for unknown type
      expect(result.errors.first.reason, contains('Unknown item type'));
    });

    test('2. Rejects encrypted Bitwarden export with clear error', () {
      final result = BitwardenParser().parse('{"encrypted": true, "items": []}');
      expect(result.items, isEmpty);
      expect(result.errors.first.reason, contains('encrypted'));
    });

    test('3. Handles invalid JSON gracefully', () {
      final result = BitwardenParser().parse('NOT JSON {{{');
      expect(result.items, isEmpty);
      expect(result.errors.first.reason, contains('Invalid JSON'));
    });
  });

  group('1Password Parser Tests', () {
    test('1. Parses login and secure note, flags unknown category', () {
      final result = OnePasswordParser().parse(_onePasswordJson);

      expect(result.items.length, equals(2));
      expect(result.errors.length, equals(1)); // categoryUuid 999

      final login = result.items[0];
      expect(login.type, equals('login'));
      expect(login.title, equals('Synthetic 1P Login'));
      expect(login.username, equals('user1p@example.com'));
      expect(login.password, equals('1pSynthPass!'));
      expect(login.urls, contains('https://1p.synthetic.example.com'));
      expect(login.notes, equals('A 1Password note'));

      final note = result.items[1];
      expect(note.type, equals('secure_note'));
      expect(note.noteContent, equals('Secret note content here.'));

      // Unknown category logged in errors
      expect(result.errors.first.reason, contains('Unsupported category UUID: 999'));
    });
  });

  group('LastPass Parser Tests', () {
    test('1. Parses 3 rows as login items with correct field mapping', () {
      final result = LastPassParser().parse(_lastPassCsv);

      // 3 data rows, all should parse
      expect(result.items.length, equals(3));
      expect(result.errors, isEmpty);

      final first = result.items[0];
      expect(first.type, equals('login'));
      expect(first.title, equals('LP Synthetic Login'));
      expect(first.username, equals('lp_user@example.com'));
      expect(first.password, equals('LpSynthPass!'));
      expect(first.totpSecret, equals('LPTOTP123'));
      expect(first.notes, equals('Some notes here'));
      expect(first.urls, contains('https://lp.example.com'));
      expect(first.favorite, isTrue);

      // Second row: fav=0 → favorite: false
      expect(result.items[1].favorite, isFalse);

      // Third row: empty url → urls is empty
      expect(result.items[2].urls, isEmpty);
    });

    test('2. Reports missing required column as error', () {
      // CSV without "name" column
      const badCsv = 'url,username,password\nhttps://x.com,u,p\n';
      final result = LastPassParser().parse(badCsv);
      expect(result.items, isEmpty);
      expect(result.errors.first.reason, contains('"name" not found'));
    });
  });

  group('Generic CSV Parser Tests', () {
    final mapping = {
      'title': 'site_name',
      'username': 'login_user',
      'password': 'secret',
      'url': 'link',
      'notes': 'description',
    };

    test('1. Parses 2 rows and flags unmapped column', () {
      final result = GenericCsvParser(columnMapping: mapping).parse(_genericCsv);

      // 2 data rows
      expect(result.items.length, equals(2));

      // Unmapped column "unknown_col" flagged twice (once per row? No — header level)
      final unmappedErrors = result.errors.where((e) => e.reason.contains('not mapped')).toList();
      expect(unmappedErrors, isNotEmpty);
      expect(unmappedErrors.first.sourceRef, equals('header'));

      // First row mapped correctly
      final item = result.items[0];
      expect(item.type, equals('login'));
      expect(item.title, equals('Synthetic Site'));
      expect(item.username, equals('gen_user@example.com'));
      expect(item.password, equals('GenSynthPass!'));
      expect(item.urls, contains('https://generic.example.com'));
      expect(item.notes, equals('Generic notes'));
    });

    test('2. Flags row without title as error, not silently dropped', () {
      const missingTitleCsv = 'site_name,login_user,secret\n,user,pass\n';
      final result = GenericCsvParser(columnMapping: {
        'title': 'site_name',
        'username': 'login_user',
        'password': 'secret',
      }).parse(missingTitleCsv);

      expect(result.items, isEmpty);
      expect(result.errors.any((e) => e.reason.contains('"title"')), isTrue);
    });
  });

  group('Encrypt-on-Commit Tests', () {
    test('1. ParsedItem can be converted to EncryptedVaultItem (no plaintext retained)', () async {
      final vaultKey = List<int>.filled(32, 42);
      final db = SqliteVaultDatabase.inMemory();
      db.open(vaultKey);
      final crypto = VaultCrypto();

      final parsed = ParsedItem(
        title: 'Synth Encrypted Item',
        type: 'login',
        username: 'cryptotest@example.com',
        password: 'EncryptMe!99',
        urls: ['https://crypto.test.example'],
        notes: 'Sensitive notes',
      );

      // Inline encrypt-and-save (mirrors import_screen.dart encryptAndSave logic)
      final now = DateTime.now().toUtc();
      final id = '${now.millisecondsSinceEpoch}_${parsed.title.hashCode.abs()}';
      final vaultItem = VaultItem(
        id: id,
        type: VaultItemType.login,
        title: parsed.title,
        tags: parsed.tags,
        favorite: parsed.favorite,
        vaultId: '',
        createdAt: now,
        updatedAt: now,
        fields: LoginFields(
          username: parsed.username ?? '',
          password: ConcealedValue.plain(parsed.password ?? ''),
          urls: parsed.urls,
          otpSecret: const ConcealedValue.plain(''),
          passwordHistory: const [],
        ),
        customFields: const [],
        notes: ConcealedValue.plain(parsed.notes ?? ''),
      );
      final encrypted = await vaultItem.encrypt(vaultKey, crypto);
      db.insertItem(encrypted);

      // Verify item is in the database as ciphertext
      final stored = db.getAllItems();
      expect(stored.length, equals(1));

      final enc = stored.first;
      // The stored blob must not contain any plaintext password
      expect(enc.encryptedBlob, isNot(contains('EncryptMe!99')));
      expect(enc.encryptedBlob, isNot(contains('cryptotest@example.com')));

      // Verify round-trip decrypt works
      final decrypted = await VaultItem.decrypt(enc, vaultKey, crypto);
      expect(decrypted.title, equals('Synth Encrypted Item'));
      final fields = decrypted.fields as LoginFields;
      expect(fields.username, equals('cryptotest@example.com'));
      expect(fields.password.plaintext, equals('EncryptMe!99'));

      db.close();
    });
  });

  group('Expanded Import Capabilities Tests', () {
    test('1. Parses Chrome CSV preset correctly', () {
      const csv = 'name,url,username,password\nGoogle,https://google.com,chromeuser,chromepass\n';
      final result = const GenericCsvParser(columnMapping: {
        'title': 'name',
        'url': 'url',
        'username': 'username',
        'password': 'password',
      }).parse(csv);

      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('Google'));
      expect(item.urls, contains('https://google.com'));
      expect(item.username, equals('chromeuser'));
      expect(item.password, equals('chromepass'));
    });

    test('2. Parses Firefox CSV preset correctly', () {
      const csv = 'url,username,password\nhttps://firefox.com,firefoxuser,firefoxpass\n';
      final result = const GenericCsvParser(columnMapping: {
        'title': 'url',
        'url': 'url',
        'username': 'username',
        'password': 'password',
      }).parse(csv);

      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('https://firefox.com'));
      expect(item.urls, contains('https://firefox.com'));
      expect(item.username, equals('firefoxuser'));
      expect(item.password, equals('firefoxpass'));
    });

    test('3. Parses Safari CSV preset correctly', () {
      const csv = 'Title,URL,Username,Password,Notes,OTPAuth\nApple,https://apple.com,safariuser,safaripass,Safari notes,safaritotp\n';
      final result = const GenericCsvParser(columnMapping: {
        'title': 'Title',
        'url': 'URL',
        'username': 'Username',
        'password': 'Password',
        'notes': 'Notes',
        'totp': 'OTPAuth',
      }).parse(csv);

      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('Apple'));
      expect(item.urls, contains('https://apple.com'));
      expect(item.username, equals('safariuser'));
      expect(item.password, equals('safaripass'));
      expect(item.notes, equals('Safari notes'));
      expect(item.totpSecret, equals('safaritotp'));
    });

    test('4. Parses Dashlane CSV correctly', () {
      const csv = 'name,url,username,password,notes,otpsecret\nDashlane Item,https://dashlane.com,dashuser,dashpass,dashnotes,dashtotp\n';
      final result = DashlaneParser().parse(csv);

      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('Dashlane Item'));
      expect(item.urls, contains('https://dashlane.com'));
      expect(item.username, equals('dashuser'));
      expect(item.password, equals('dashpass'));
      expect(item.notes, equals('dashnotes'));
      expect(item.totpSecret, equals('dashtotp'));
    });

    test('5. Parses Keeper CSV correctly', () {
      const csv = 'Title,Login,Password,Website Address,Notes\nKeeper Item,keeperuser,keeperpass,https://keeper.com,keepernotes\n';
      final result = KeeperParser().parse(csv);

      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('Keeper Item'));
      expect(item.urls, contains('https://keeper.com'));
      expect(item.username, equals('keeperuser'));
      expect(item.password, equals('keeperpass'));
      expect(item.notes, equals('keepernotes'));
    });

    test('6. Parses NordPass CSV correctly', () {
      const csv = 'name,username,password,url,note\nNordPass Item,norduser,nordpass,https://nordpass.com,nordnotes\n';
      final result = NordPassParser().parse(csv);

      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('NordPass Item'));
      expect(item.urls, contains('https://nordpass.com'));
      expect(item.username, equals('norduser'));
      expect(item.password, equals('nordpass'));
      expect(item.notes, equals('nordnotes'));
    });

    test('7. Parses RoboForm CSV correctly', () {
      const csv = 'name,login,pwd,url,note\nRoboForm Item,robouser,robopass,https://roboform.com,robonotes\n';
      final result = RoboFormParser().parse(csv);

      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('RoboForm Item'));
      expect(item.urls, contains('https://roboform.com'));
      expect(item.username, equals('robouser'));
      expect(item.password, equals('robopass'));
      expect(item.notes, equals('robonotes'));
    });

    test('8. Parses Proton Pass JSON correctly', () {
      const json = '''
      {
        "vaults": [
          {
            "name": "Personal",
            "items": [
              {
                "data": {
                  "metadata": {
                    "name": "Proton Item",
                    "note": "protonnotes"
                  },
                  "content": {
                    "username": "protonuser",
                    "password": "protonpass",
                    "urls": ["https://proton.me"],
                    "totpUri": "protontotp"
                  }
                }
              }
            ]
          }
        ]
      }
      ''';
      final result = ProtonPassParser().parse(json);

      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('Proton Item'));
      expect(item.urls, contains('https://proton.me'));
      expect(item.username, equals('protonuser'));
      expect(item.password, equals('protonpass'));
      expect(item.notes, equals('protonnotes'));
      expect(item.totpSecret, equals('protontotp'));
    });

    test('9. Decrypts and parses KeePass KDBX database correctly, and scrubs credentials', () async {
      // 1. Programmatically construct a synthetic KDBX database in memory using composite credentials
      final keyFileBytes = Uint8List.fromList([1, 2, 3, 4]);
      final keyFileBytesForCreate = Uint8List.fromList(keyFileBytes);
      final kdbx = KdbxFormat().create(
        Credentials.composite(ProtectedValue.fromString('dbpassword'), keyFileBytesForCreate),
        'Test DB',
      );
      final group = kdbx.body.rootGroup;
      final entry = KdbxEntry.create(kdbx, group);
      group.addEntry(entry);
      entry.setString(KdbxKeyCommon.TITLE, PlainValue('KeePass Title'));
      entry.setString(KdbxKeyCommon.USER_NAME, PlainValue('keepassuser'));
      entry.setString(KdbxKeyCommon.PASSWORD, ProtectedValue.fromString('keepasspass'));
      entry.setString(KdbxKeyCommon.URL, PlainValue('https://keepass.info'));
      entry.setString(KdbxKey('Notes'), PlainValue('keepassnotes'));
      entry.setString(KdbxKey('otp'), PlainValue('keepasstotp'));

      final bytes = await KdbxFormat().save(kdbx, (bytes) async {
        return Uint8List.fromList(bytes);
      });

      // 2. Parse it using KeePassKdbxParser
      final result = await KeePassKdbxParser().parse(
        bytes: bytes,
        password: 'dbpassword',
        keyFileBytes: keyFileBytes,
      );

      // 3. Verify items parsed correctly
      if (result.errors.isNotEmpty) {
        print('KeePass parse errors: ${result.errors.map((e) => "${e.sourceRef}: ${e.reason}").toList()}');
      }
      expect(result.items.length, equals(1));
      expect(result.errors, isEmpty);
      final item = result.items[0];
      expect(item.title, equals('KeePass Title'));
      expect(item.username, equals('keepassuser'));
      expect(item.password, equals('keepasspass'));
      expect(item.urls, contains('https://keepass.info'));
      expect(item.notes, equals('keepassnotes'));
      expect(item.totpSecret, equals('keepasstotp'));

      // 4. Verify memory scrubbing: keyFileBytes should be zeroed out
      expect(keyFileBytes, equals(Uint8List.fromList([0, 0, 0, 0])));
    });
  });
}
