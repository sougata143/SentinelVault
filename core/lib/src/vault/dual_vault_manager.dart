import '../database/vault_database.dart';
import '../models/models.dart';
import '../models/vault_item.dart';
import '../crypto/crypto.dart';

/// Manages the dual-vault architecture for the Duress/Decoy feature.
///
/// Vault Alpha = real vault (Master Password derived, unchanged).
/// Vault Beta  = decoy vault (Duress Password derived, independent keys/salts).
///
/// This class is responsible only for populating Vault Beta at setup time.
/// Key storage and verification live in [DuressWipeHook] and [SecureStorage].
class DualVaultManager {
  static final DualVaultManager instance = DualVaultManager._internal();
  DualVaultManager._internal();

  // SecureStorage keys for the decoy vault configuration.
  static const String duressSaltKey = 'duress_salt';
  static const String duressWrappedKeyKey = 'duress_wrapped_vault_key';
  static const String duressConfiguredKey = 'duress_configured';

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
      vaultId: '',
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

    // 2. Decoy Credit Card Item (limit note avoids '$' interpolation)
    final decoyCc = VaultItem(
      id: 'decoy-cc-1',
      type: VaultItemType.creditCard,
      title: 'Shopping Credit Card',
      tags: const [],
      favorite: false,
      vaultId: '',
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
      vaultId: '',
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
