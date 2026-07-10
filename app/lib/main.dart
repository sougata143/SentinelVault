import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'app_shell.dart';
import 'theme/theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SentinelVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const VaultHomeScreen(),
    );
  }
}

class VaultHomeScreen extends StatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  State<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends State<VaultHomeScreen> {
  late final VaultDatabase _db;
  final List<int> _vaultKey = List<int>.filled(32, 1); // 256-bit vault key placeholder

  @override
  void initState() {
    super.initState();
    // Initialize in-memory database
    _db = SqliteVaultDatabase.inMemory();
    _db.open(_vaultKey);

    _prepopulateMockData();
  }

  void _prepopulateMockData() {
    final now = DateTime.now().toUtc();
    final crypto = VaultCrypto();

    // 1. Prepopulate a legacy Phase 4 item to verify automatic database migration
    final legacyItem = EncryptedVaultItem(
      id: 'legacy-1',
      encryptedBlob: 'encrypted:Google Workspace:user@gmail.com:correcthorsebatterystaple',
      nonce: 'dummy-nonce-legacy',
      version: 1,
      updatedAt: now,
    );

    // 2. Prepopulate a new double-encrypted Credit Card item
    final ccItem = VaultItem(
      id: 'new-cc-2',
      type: VaultItemType.creditCard,
      title: 'Visa Corporate Card',
      tags: ['work', 'finance'],
      favorite: true,
      vaultId: 'default-vault',
      createdAt: now,
      updatedAt: now,
      notes: const ConcealedValue.plain('Keep this secure.'),
      customFields: const [],
      fields: CreditCardFields(
        cardholderName: 'Alice Auditor',
        cardNumber: const ConcealedValue.plain('4111222233334444'),
        brand: 'visa',
        expiryMonth: 9,
        expiryYear: 2029,
        cvv: const ConcealedValue.plain('998'),
        pin: const ConcealedValue.plain('0077'),
      ),
    );

    // Insert items
    _db.insertItem(legacyItem);

    // Encrypt CC item before insertion
    ccItem.encrypt(_vaultKey, crypto).then((enc) {
      _db.insertItem(enc);
    });
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      db: _db,
      vaultKey: _vaultKey,
    );
  }
}
