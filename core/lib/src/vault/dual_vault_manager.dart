import 'dart:convert';
import '../database/vault_database.dart';
import '../models/models.dart';
import '../models/vault_item.dart';
import '../crypto/crypto.dart';
import '../platform/secure_storage.dart';

/// Container returned when setting up a Decoy Vault.
class DecoyVaultSetupResult {
  /// Base64-encoded random salt for the decoy vault.
  final String saltBase64;
  /// Base64-encoded wrapped decoy vault key payload.
  final String wrappedVaultKeyBase64;
  /// The unwrapped 32-byte decoy vault key bytes.
  final List<int> decoyVaultKey;

  /// Creates a new [DecoyVaultSetupResult] instance.
  const DecoyVaultSetupResult({
    required this.saltBase64,
    required this.wrappedVaultKeyBase64,
    required this.decoyVaultKey,
  });
}

/// Manages the dual-vault architecture for the Duress/Decoy feature.
///
/// Vault Alpha = real vault (Master Password derived, unchanged).
/// Vault Beta  = decoy vault (Duress Password derived, independent keys/salts).
///
/// Security Invariant (AGENTS.md Rule 14):
/// Entering a Duress Password triggers [triggerDuressWipeHook] to invalidate
/// Vault Alpha's biometric quick-unlock cache, but NEVER deletes or touches
/// Vault Alpha's actual encrypted SQLite or remote data.
class DualVaultManager {
  /// The global singleton instance of the dual vault manager.
  static final DualVaultManager instance = DualVaultManager._internal();
  DualVaultManager._internal();

  /// SecureStorage key storing the salt used to derive the decoy vault's keys.
  static const String duressSaltKey = 'duress_salt';

  /// SecureStorage key storing the wrapped decoy vault key.
  static const String duressWrappedKeyKey = 'duress_wrapped_vault_key';

  /// SecureStorage key storing whether duress/decoy vault is enabled.
  static const String duressConfiguredKey = 'duress_configured';

  /// Configures and initializes an independent Decoy Vault (Vault Beta).
  Future<DecoyVaultSetupResult> setupDecoyVault({
    required String duressPassword,
    required VaultCrypto crypto,
  }) async {
    final saltBeta = crypto.generateRandomBytes(16);
    final masterKeyBeta = await crypto.deriveMasterKey(
      masterPassword: duressPassword,
      salt: saltBeta,
    );
    final vaultKeyBeta = crypto.generateRandomBytes(32);
    final wrappedVaultKeyBeta = await crypto.wrapVaultKey(
      vaultKey: vaultKeyBeta,
      masterKey: masterKeyBeta,
    );

    final saltBase64 = base64.encode(saltBeta);
    final wrappedVaultKeyBase64 = base64.encode(wrappedVaultKeyBeta);

    await SecureStorage.instance.writeString(duressSaltKey, saltBase64);
    await SecureStorage.instance.writeString(duressWrappedKeyKey, wrappedVaultKeyBase64);
    await SecureStorage.instance.writeString(duressConfiguredKey, 'true');

    return DecoyVaultSetupResult(
      saltBase64: saltBase64,
      wrappedVaultKeyBase64: wrappedVaultKeyBase64,
      decoyVaultKey: vaultKeyBeta,
    );
  }

  /// Returns true if a decoy vault is currently configured.
  Future<bool> isDecoyConfigured() async {
    final flag = await SecureStorage.instance.readString(duressConfiguredKey);
    return flag == 'true';
  }

  /// Attempts to unlock the Decoy Vault using [password].
  /// Returns the 32-byte Vault Key Beta if successful, or null if incorrect.
  Future<List<int>?> unlockDecoyVault({
    required String password,
    required VaultCrypto crypto,
  }) async {
    final saltBase64 = await SecureStorage.instance.readString(duressSaltKey);
    final wrappedBase64 = await SecureStorage.instance.readString(duressWrappedKeyKey);

    if (saltBase64 == null || wrappedBase64 == null) {
      return null;
    }

    try {
      final saltBeta = base64.decode(saltBase64);
      final wrappedBeta = base64.decode(wrappedBase64);

      final masterKeyBeta = await crypto.deriveMasterKey(
        masterPassword: password,
        salt: saltBeta,
      );

      return await crypto.unwrapVaultKey(
        wrappedVaultKey: wrappedBeta,
        masterKey: masterKeyBeta,
      );
    } catch (_) {
      return null;
    }
  }

  /// Prepopulates Vault Beta (decoy) with harmless, plausible items.
  ///
  /// [db] must already be open and keyed with [vaultKey] before calling this.
  Future<void> prepopulateDecoyItems(VaultDatabase db, List<int> vaultKey) async {
    final now = DateTime.now().toUtc();
    final crypto = VaultCrypto();

    // 1. Decoy Login Item
    final decoyLogin = VaultItem(
      id: 'decoy-login-1',
      type: VaultItemType.login,
      title: 'Google Workspace Account',
      tags: const ['work'],
      favorite: false,
      vaultId: 'vault-beta',
      createdAt: now,
      updatedAt: now,
      notes: const ConcealedValue.plain('Work-related backup account.'),
      customFields: const [],
      fields: LoginFields(
        username: 'backup.audit.vault@gmail.com',
        password: const ConcealedValue.plain('correcthorsebatterystaple'),
        urls: const ['https://workspace.google.com'],
        otpSecret: const ConcealedValue.plain(''),
        passwordHistory: const [],
      ),
    );
    final encLogin = await decoyLogin.encrypt(vaultKey, crypto);
    db.insertItem(encLogin);

    // 2. Decoy Credit Card Item
    final decoyCc = VaultItem(
      id: 'decoy-cc-1',
      type: VaultItemType.creditCard,
      title: 'Shopping Credit Card',
      tags: const [],
      favorite: false,
      vaultId: 'vault-beta',
      createdAt: now,
      updatedAt: now,
      notes: const ConcealedValue.plain('Daily small transactions.'),
      customFields: const [],
      fields: CreditCardFields(
        cardholderName: 'Security Auditor',
        cardNumber: const ConcealedValue.plain('4111222233334444'),
        brand: 'Visa',
        expiryMonth: 9,
        expiryYear: 2030,
        cvv: const ConcealedValue.plain('999'),
        pin: const ConcealedValue.plain('1234'),
      ),
    );
    final encCc = await decoyCc.encrypt(vaultKey, crypto);
    db.insertItem(encCc);

    // 3. Decoy Secure Note
    final decoyNote = VaultItem(
      id: 'decoy-note-1',
      type: VaultItemType.secureNote,
      title: 'Personal To-Do List',
      tags: const [],
      favorite: false,
      vaultId: 'vault-beta',
      createdAt: now,
      updatedAt: now,
      notes: const ConcealedValue.plain('General tasks list.'),
      customFields: const [],
      fields: SecureNoteFields(
        content: const ConcealedValue.plain(
          '1. Update cloud backups.\n2. Review docs.\n3. Setup emergency kit.',
        ),
      ),
    );
    final encNote = await decoyNote.encrypt(vaultKey, crypto);
    db.insertItem(encNote);
  }
}
