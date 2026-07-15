import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'app_shell.dart';
import 'theme/theme.dart';
import 'features/auth/flutter_secure_storage_impl.dart';
import 'features/auth/route_guard.dart';
import 'features/native_messaging/local_messaging_server.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web-only: block until the WASM crypto module loaded by index.html is
  // fully initialised.  This prevents the NoSuchMethodError that occurs when
  // Dart calls into wasmEncryptAesGcm before wasm-bindgen's async init()
  // has resolved.  On native/io this is a no-op (ensureWasmReady returns
  // immediately from the io/stub implementation).
  await ensureWasmReady();

  // Register real platform-backed secure storage
  SecureStorage.instance = FlutterPlatformSecureStorage();
  
  // Clear any cached biometric keys from secure storage on startup to enforce
  // the restart policy (biometric cache is only valid for in-app locks).
  // We catch any platform-channel or keystore error here: if the wipe fails on
  // startup the user still must enter their Master Password, so the vault
  // remains secure. The error is already logged inside deleteBiometricWrappedVaultKey.
  try {
    await SecureStorage.instance.deleteBiometricWrappedVaultKey();
  } catch (_) {
    // Intentional: logged inside deleteBiometricWrappedVaultKey; do not crash on boot.
  }
  
  // Load session from secure storage
  await VaultLockManager.instance.loadSession();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final Widget? home;
  const MyApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SentinelVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: home ?? const RouteGuard(),
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
    LocalMessagingServer.db = _db;
    LocalMessagingServer.start();
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
    LocalMessagingServer.stop();
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
