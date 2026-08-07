import 'dart:convert';
import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('New Vault Templates & Attachments Core Tests', () {
    late List<int> vaultKey;
    late VaultCrypto crypto;

    setUp(() {
      crypto = VaultCrypto();
      vaultKey = crypto.generateRandomBytes(32);
    });

    test('SSH Key Pair Fields encryption and decryption round-trip', () async {
      final fields = SshKeyFields(
        keyName: 'Production Server Ed25519',
        privateKey: const ConcealedValue.plain('-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAAAA...\n-----END OPENSSH PRIVATE KEY-----'),
        publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...',
        passphrase: const ConcealedValue.plain('super-secret-ssh-passphrase'),
        keyType: 'Ed25519',
      );

      final encFields = await fields.encrypt(vaultKey, crypto);
      expect(encFields.privateKey.isEncrypted, isTrue);
      expect(encFields.passphrase.isEncrypted, isTrue);

      final decFields = await encFields.decrypt(vaultKey, crypto);
      expect(decFields.keyName, equals('Production Server Ed25519'));
      expect(decFields.privateKey.plaintext, contains('BEGIN OPENSSH PRIVATE KEY'));
      expect(decFields.publicKey, contains('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
      expect(decFields.passphrase.plaintext, equals('super-secret-ssh-passphrase'));
      expect(decFields.keyType, equals('Ed25519'));
    });

    test('API Key / Token Fields encryption and decryption round-trip', () async {
      final fields = ApiKeyFields(
        serviceName: 'OpenAI Platform',
        keyValue: const ConcealedValue.plain('sk-proj-1234567890abcdefghijklmnopqrstuvwxyz'),
        apiSecret: const ConcealedValue.plain('sec-signing-key-9999'),
        expiryDate: '2027-12-31',
        notes: 'Production API key for Gemini / LLM models',
      );

      final encFields = await fields.encrypt(vaultKey, crypto);
      expect(encFields.keyValue.isEncrypted, isTrue);
      expect(encFields.apiSecret.isEncrypted, isTrue);

      final decFields = await encFields.decrypt(vaultKey, crypto);
      expect(decFields.serviceName, equals('OpenAI Platform'));
      expect(decFields.keyValue.plaintext, equals('sk-proj-1234567890abcdefghijklmnopqrstuvwxyz'));
      expect(decFields.apiSecret.plaintext, equals('sec-signing-key-9999'));
      expect(decFields.expiryDate, equals('2027-12-31'));
      expect(decFields.notes, equals('Production API key for Gemini / LLM models'));
    });

    test('Crypto Wallet Seed Phrase Fields encryption and decryption round-trip', () async {
      final fields = CryptoSeedFields(
        walletName: 'MetaMask Primary Hardware Backup',
        seedPhrase: const ConcealedValue.plain('abandon amount isolate cheap expire fuel heavy position primary sward vary wisdom'),
        derivationPath: "m/44'/60'/0'/0/0",
        notes: 'Ethereum mainnet account 0x123...abc',
      );

      final encFields = await fields.encrypt(vaultKey, crypto);
      expect(encFields.seedPhrase.isEncrypted, isTrue);

      final decFields = await encFields.decrypt(vaultKey, crypto);
      expect(decFields.walletName, equals('MetaMask Primary Hardware Backup'));
      expect(decFields.seedPhrase.plaintext, equals('abandon amount isolate cheap expire fuel heavy position primary sward vary wisdom'));
      expect(decFields.derivationPath, equals("m/44'/60'/0'/0/0"));
      expect(decFields.notes, equals('Ethereum mainnet account 0x123...abc'));
    });

    test('Software License Fields encryption and decryption round-trip', () async {
      final fields = SoftwareLicenseFields(
        productName: 'JetBrains All Products Pack',
        licenseKey: const ConcealedValue.plain('A1B2C-D3E4F-G5H6I-J7K8L-M9N0P'),
        purchaseDate: '2026-01-15',
        seatsOrVersion: '5 Seats / v2026.1',
        vendor: 'JetBrains s.r.o.',
      );

      final encFields = await fields.encrypt(vaultKey, crypto);
      expect(encFields.licenseKey.isEncrypted, isTrue);

      final decFields = await encFields.decrypt(vaultKey, crypto);
      expect(decFields.productName, equals('JetBrains All Products Pack'));
      expect(decFields.licenseKey.plaintext, equals('A1B2C-D3E4F-G5H6I-J7K8L-M9N0P'));
      expect(decFields.purchaseDate, equals('2026-01-15'));
      expect(decFields.seatsOrVersion, equals('5 Seats / v2026.1'));
      expect(decFields.vendor, equals('JetBrains s.r.o.'));
    });

    test('Secure Note with zero-knowledge file attachment payload encryption/decryption', () async {
      final rawFilePayload = utf8.encode('Top Secret Contract File Content 2026');
      final base64File = base64.encode(rawFilePayload);

      final attachment = VaultItemAttachment(
        id: 'att-uuid-1001',
        fileName: 'contract_confidential.pdf',
        mimeType: 'application/pdf',
        fileSize: rawFilePayload.length,
        encryptedData: ConcealedValue.plain(base64File),
      );

      final noteFields = SecureNoteFields(
        content: const ConcealedValue.plain('Highly confidential board meeting minutes'),
        attachments: [attachment],
      );

      final item = VaultItem(
        id: 'item-uuid-2002',
        type: VaultItemType.secureNote,
        title: 'Executive Board Note & Contract',
        tags: ['confidential', 'executive'],
        favorite: true,
        vaultId: 'v1',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        fields: noteFields,
        customFields: const [],
        notes: const ConcealedValue.plain('Internal board note'),
      );

      // Encrypt full item envelope
      final encItem = await item.encrypt(vaultKey, crypto);
      expect(encItem.encryptedBlob, isNotEmpty);

      // Decrypt full item envelope
      final decItem = await VaultItem.decrypt(encItem, vaultKey, crypto);
      expect(decItem.title, equals('Executive Board Note & Contract'));
      expect(decItem.type, equals(VaultItemType.secureNote));

      final decNoteFields = decItem.fields as SecureNoteFields;
      expect(decNoteFields.content.plaintext, equals('Highly confidential board meeting minutes'));
      expect(decNoteFields.attachments.length, equals(1));

      final decAtt = decNoteFields.attachments.first;
      expect(decAtt.fileName, equals('contract_confidential.pdf'));
      expect(decAtt.mimeType, equals('application/pdf'));

      final decBase64 = decAtt.encryptedData.plaintext;
      expect(decBase64, isNotNull);
      final decBytes = base64.decode(decBase64!);
      expect(utf8.decode(decBytes), equals('Top Secret Contract File Content 2026'));
    });
  });
}
