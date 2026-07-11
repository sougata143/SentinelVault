import '../platform/secure_storage.dart';

/// Native duress hook that building on native-secure-storage to immediately
/// invalidate Vault Alpha's biometric-cached key.
///
/// Under coercion, when the user enters the decoy vault password, this hook
/// is fired to wipe Vault Alpha's quick-unlock credentials from secure storage.
/// This prevents Vault Alpha from being unlocked via biometrics/quick unlock on this device
/// until the full Master Password is manually re-entered, without touching
/// Vault Alpha's actual encrypted SQLite/local data.
Future<void> triggerDuressWipeHook() async {
  // Wipe the biometric-cached wrapped vault key from platform Keychain/Keystore
  await SecureStorage.instance.deleteBiometricWrappedVaultKey();
}
