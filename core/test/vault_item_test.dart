import 'dart:convert';
import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('VaultItem Multi-Type Schema Tests', () {
    late VaultCrypto crypto;
    late List<int> vaultKey;

    setUp(() {
      crypto = VaultCrypto();
      vaultKey = List.generate(32, (i) => i);
    });

    test('1. Login item round-trip encryption/decryption', () async {
      final loginItem = VaultItem(
        id: 'login-uuid',
        type: VaultItemType.login,
        title: 'Google Account',
        tags: ['work', 'personal'],
        favorite: true,
        vaultId: 'vault-uuid',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        notes: const ConcealedValue.plain('Some sensitive notes here'),
        customFields: [
          CustomField(
            label: 'PIN',
            type: 'concealed',
            value: const ConcealedValue.plain('9988'),
          ),
          CustomField(
            label: 'Secondary Email',
            type: 'text',
            value: const ConcealedValue.plain('recovery@gmail.com'),
          ),
        ],
        fields: LoginFields(
          username: 'user@gmail.com',
          password: const ConcealedValue.plain('StrongPassword123!'),
          urls: ['https://google.com', 'https://accounts.google.com'],
          otpSecret: const ConcealedValue.plain('JBSWY3DPEHPK3PXP'),
          passwordHistory: [
            PasswordHistoryEntry(
              password: const ConcealedValue.plain('OldPassword99!'),
              changedAt: DateTime.now().subtract(const Duration(days: 30)).toUtc(),
            ),
          ],
        ),
      );

      // Encrypt
      final encrypted = await loginItem.encrypt(vaultKey, crypto);
      expect(encrypted.id, equals('login-uuid'));
      expect(encrypted.encryptedBlob, isNot(contains('StrongPassword123!')));

      // Decrypt
      final decrypted = await VaultItem.decrypt(encrypted, vaultKey, crypto);
      expect(decrypted.id, equals('login-uuid'));
      expect(decrypted.type, equals(VaultItemType.login));
      expect(decrypted.title, equals('Google Account'));
      expect(decrypted.tags, containsAll(['work', 'personal']));
      expect(decrypted.favorite, isTrue);

      final loginFields = decrypted.fields as LoginFields;
      expect(loginFields.username, equals('user@gmail.com'));
      expect(loginFields.password.plaintext, equals('StrongPassword123!'));
      expect(loginFields.otpSecret.plaintext, equals('JBSWY3DPEHPK3PXP'));
      expect(loginFields.passwordHistory.first.password.plaintext, equals('OldPassword99!'));

      expect(decrypted.notes.plaintext, equals('Some sensitive notes here'));
      expect(decrypted.customFields[0].value.plaintext, equals('9988'));
      expect(decrypted.customFields[1].value.plaintext, equals('recovery@gmail.com'));
    });

    test('2. Credit Card item round-trip encryption/decryption', () async {
      final ccItem = VaultItem(
        id: 'cc-uuid',
        type: VaultItemType.creditCard,
        title: 'Visa Gold',
        tags: ['finance'],
        favorite: false,
        vaultId: 'vault-uuid',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: CreditCardFields(
          cardholderName: 'John Doe',
          cardNumber: const ConcealedValue.plain('4111222233334444'),
          brand: 'visa',
          expiryMonth: 12,
          expiryYear: 2028,
          cvv: const ConcealedValue.plain('123'),
          pin: const ConcealedValue.plain('4321'),
        ),
      );

      final encrypted = await ccItem.encrypt(vaultKey, crypto);
      final decrypted = await VaultItem.decrypt(encrypted, vaultKey, crypto);

      expect(decrypted.type, equals(VaultItemType.creditCard));
      expect(decrypted.title, equals('Visa Gold'));

      final ccFields = decrypted.fields as CreditCardFields;
      expect(ccFields.cardholderName, equals('John Doe'));
      expect(ccFields.cardNumber.plaintext, equals('4111222233334444'));
      expect(ccFields.brand, equals('visa'));
      expect(ccFields.expiryMonth, equals(12));
      expect(ccFields.expiryYear, equals(2028));
      expect(ccFields.cvv.plaintext, equals('123'));
      expect(ccFields.pin.plaintext, equals('4321'));
    });

    test('3. Identity item round-trip encryption/decryption', () async {
      final identityItem = VaultItem(
        id: 'id-uuid',
        type: VaultItemType.identity,
        title: 'My Profile',
        tags: const [],
        favorite: false,
        vaultId: 'vault-uuid',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: IdentityFields(
          firstName: 'Alice',
          lastName: 'Smith',
          birthdate: '1990-01-01',
          gender: 'female',
          address: IdentityAddress(
            street: '123 Main St',
            city: 'Boston',
            state: 'MA',
            zip: '02108',
            country: 'USA',
          ),
          emails: ['alice@example.com'],
          phoneNumbers: ['555-0199'],
        ),
      );

      final encrypted = await identityItem.encrypt(vaultKey, crypto);
      final decrypted = await VaultItem.decrypt(encrypted, vaultKey, crypto);

      expect(decrypted.type, equals(VaultItemType.identity));
      expect(decrypted.title, equals('My Profile'));

      final idFields = decrypted.fields as IdentityFields;
      expect(idFields.firstName, equals('Alice'));
      expect(idFields.lastName, equals('Smith'));
      expect(idFields.address.street, equals('123 Main St'));
      expect(idFields.address.city, equals('Boston'));
    });

    test('4. Secure Note item round-trip encryption/decryption', () async {
      final noteItem = VaultItem(
        id: 'note-uuid',
        type: VaultItemType.secureNote,
        title: 'Server Config Root Password',
        tags: ['security'],
        favorite: true,
        vaultId: 'vault-uuid',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: SecureNoteFields(
          content: const ConcealedValue.plain('root_secret_payload_notes_here'),
        ),
      );

      final encrypted = await noteItem.encrypt(vaultKey, crypto);
      final decrypted = await VaultItem.decrypt(encrypted, vaultKey, crypto);

      expect(decrypted.type, equals(VaultItemType.secureNote));
      expect((decrypted.fields as SecureNoteFields).content.plaintext, equals('root_secret_payload_notes_here'));
    });

    test('5. Bank Account item round-trip encryption/decryption', () async {
      final bankItem = VaultItem(
        id: 'bank-uuid',
        type: VaultItemType.bankAccount,
        title: 'Checking Account',
        tags: const [],
        favorite: false,
        vaultId: 'vault-uuid',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: BankAccountFields(
          bankName: 'Chase Bank',
          accountType: 'checking',
          accountNumber: const ConcealedValue.plain('123456789'),
          routingNumber: const ConcealedValue.plain('987654321'),
          iban: 'US89CHASE12345',
          swift: 'CHASEUS33',
        ),
      );

      final encrypted = await bankItem.encrypt(vaultKey, crypto);
      final decrypted = await VaultItem.decrypt(encrypted, vaultKey, crypto);

      expect(decrypted.type, equals(VaultItemType.bankAccount));
      final bankFields = decrypted.fields as BankAccountFields;
      expect(bankFields.bankName, equals('Chase Bank'));
      expect(bankFields.accountNumber.plaintext, equals('123456789'));
      expect(bankFields.routingNumber.plaintext, equals('987654321'));
      expect(bankFields.iban, equals('US89CHASE12345'));
    });

    test('6. Standalone Password item round-trip encryption/decryption', () async {
      final passwordItem = VaultItem(
        id: 'pw-uuid',
        type: VaultItemType.password,
        title: 'Standalone Vault Secret',
        tags: const [],
        favorite: false,
        vaultId: 'vault-uuid',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: PasswordFields(
          password: const ConcealedValue.plain('StandalonePasswordValue'),
        ),
      );

      final encrypted = await passwordItem.encrypt(vaultKey, crypto);
      final decrypted = await VaultItem.decrypt(encrypted, vaultKey, crypto);

      expect(decrypted.type, equals(VaultItemType.password));
      expect((decrypted.fields as PasswordFields).password.plaintext, equals('StandalonePasswordValue'));
    });

    test('7. Verification of inner field-level secret encryption', () async {
      final loginItem = VaultItem(
        id: 'test-uuid',
        type: VaultItemType.login,
        title: 'Secure Account',
        tags: const [],
        favorite: false,
        vaultId: 'vault-uuid',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        notes: const ConcealedValue.plain(''),
        customFields: const [],
        fields: LoginFields(
          username: 'admin',
          password: const ConcealedValue.plain('AdminPasswordSecret'),
          urls: const [],
          otpSecret: const ConcealedValue.plain(''),
          passwordHistory: const [],
        ),
      );

      // Verify that after calling .encrypt(), the serialized JSON envelope does not contain
      // plaintext secrets but instead contains ciphertext/nonce parameters.
      final encrypted = await loginItem.encrypt(vaultKey, crypto);

      // Outer decrypt manually so we can inspect the raw serialized JSON of the inner envelope
      final outerCiphertextBytes = base64.decode(encrypted.encryptedBlob);
      final outerNonceBytes = base64.decode(encrypted.nonce);

      final decryptedBytes = await crypto.decryptAesGcm(
        ciphertextAndMac: outerCiphertextBytes,
        key: vaultKey,
        nonce: outerNonceBytes,
      );

      final jsonStr = utf8.decode(decryptedBytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 1. Password field check
      final fieldsJson = map['fields'] as Map<String, dynamic>;
      final passwordJson = fieldsJson['password'] as Map<String, dynamic>;

      expect(passwordJson.containsKey('ciphertext'), isTrue);
      expect(passwordJson.containsKey('nonce'), isTrue);
      expect(passwordJson.containsKey('plaintext'), isFalse);
      expect(passwordJson['ciphertext'], isNot(equals('AdminPasswordSecret')));
    });

    test('8. Legacy Phase 4 migration decodes cleanly to type: "login"', () async {
      // Mock Phase 4 legacy plaintext format item
      final legacyItem = EncryptedVaultItem(
        id: 'legacy-id-123',
        encryptedBlob: 'encrypted:Google Account:user@gmail.com:123456',
        nonce: 'dummy-nonce',
        version: 1,
        updatedAt: DateTime.now().toUtc(),
      );

      // Decrypt the legacy item
      final migratedItem = await VaultItem.decrypt(legacyItem, vaultKey, crypto);

      expect(migratedItem.id, equals('legacy-id-123'));
      expect(migratedItem.type, equals(VaultItemType.login));
      expect(migratedItem.title, equals('Google Account'));
      
      final loginFields = migratedItem.fields as LoginFields;
      expect(loginFields.username, equals('user@gmail.com'));
      expect(loginFields.password.plaintext, equals('123456'));
    });
  });
}
