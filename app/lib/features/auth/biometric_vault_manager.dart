import 'dart:io';
import 'package:local_auth/local_auth.dart';
import 'package:core/core.dart';

/// Manages biometric-gated vault key caching in platform secure hardware storage
/// (iOS Keychain, Android Keystore, Windows Credential Manager / DPAPI).
///
/// Security Guarantees:
/// 1. Master Password is NEVER cached or stored anywhere.
/// 2. Only the derived 32-byte Vault Key is sealed in platform secure storage.
/// 3. Key unsealing requires passing OS biometric prompt via [local_auth].
/// 4. Disabling biometrics or explicit locking immediately purges all cached key material.
///
/// Storage Architecture:
/// Simple flags and TTL settings use [SecureStorage.instance] (injectable, testable).
/// The actual biometric-wrapped key blob is delegated to [VaultLockManager.enableBiometrics]
/// which also uses [SecureStorage.instance.writeBiometricWrappedVaultKey].
class BiometricVaultManager {
  static final _auth = LocalAuthentication();

  static const String keyCachedVaultKey = 'sentinel_cached_vault_key';
  static const String keyCachedTimestamp = 'sentinel_vault_key_cached_at';
  static const String keyBiometricsEnabled = 'sentinel_biometrics_enabled';
  static const String keyAutoLockTtlSeconds = 'sentinel_auto_lock_ttl_seconds';

  /// Default inactivity TTL: 15 minutes (900 seconds)
  static const int defaultTtlSeconds = 900;

  /// Override for [isBiometricAvailable] used in widget tests to simulate
  /// device support without a real platform biometric channel.
  static bool? isBiometricAvailableOverride;

  /// Checks if hardware biometric authentication is available on the device.
  static Future<bool> isBiometricAvailable() async {
    if (isBiometricAvailableOverride != null) {
      return isBiometricAvailableOverride!;
    }
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canAuthenticateWithBiometrics || isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Returns a platform-appropriate display label for the primary biometric sensor.
  static Future<String> getBiometricLabel() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      if (Platform.isIOS || Platform.isMacOS) {
        if (available.contains(BiometricType.face)) {
          return 'Face ID';
        }
        if (available.contains(BiometricType.fingerprint) || available.contains(BiometricType.strong)) {
          return 'Touch ID';
        }
      }
      if (Platform.isAndroid) {
        if (available.contains(BiometricType.face)) {
          return 'Face Unlock';
        }
        if (available.contains(BiometricType.fingerprint) || available.contains(BiometricType.strong)) {
          return 'Fingerprint';
        }
      }
      if (Platform.isWindows) {
        return 'Windows Hello';
      }
    } catch (_) {}
    return 'Biometrics';
  }

  /// Checks whether the user has enabled biometric unlock in Settings.
  /// Uses [SecureStorage.instance] so that widget tests can use the in-memory backend.
  static Future<bool> isBiometricsEnabled() async {
    final val = await SecureStorage.instance.readString(keyBiometricsEnabled);
    return val == 'true';
  }

  /// Sets the biometric unlock setting state.
  /// If disabled, immediately purges any cached Vault Key from secure storage.
  /// Uses [SecureStorage.instance] so that widget tests can use the in-memory backend.
  static Future<void> setBiometricsEnabled(bool enabled) async {
    await SecureStorage.instance.writeString(keyBiometricsEnabled, enabled ? 'true' : 'false');
    if (!enabled) {
      await purgeCachedKey();
    }
  }

  /// Gets the configured auto-lock TTL in seconds.
  static Future<int> getAutoLockTtlSeconds() async {
    final val = await SecureStorage.instance.readString(keyAutoLockTtlSeconds);
    if (val != null) {
      final parsed = int.tryParse(val);
      if (parsed != null) return parsed;
    }
    return defaultTtlSeconds;
  }

  /// Sets the auto-lock TTL in seconds.
  static Future<void> setAutoLockTtlSeconds(int seconds) async {
    await SecureStorage.instance.writeString(keyAutoLockTtlSeconds, seconds.toString());
  }

  /// Seals the 32-byte derived Vault Key inside platform secure hardware storage.
  ///
  /// [vaultKey] must be the raw 32-byte key array. The Master Password is NEVER passed here.
  static Future<void> cacheVaultKey(List<int> vaultKey) async {
    final enabled = await isBiometricsEnabled();
    if (!enabled) return;

    final hexKey = vaultKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await SecureStorage.instance.writeString(keyCachedVaultKey, hexKey);
    await SecureStorage.instance.writeString(
      keyCachedTimestamp,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Checks if a valid cached Vault Key exists and has not expired past configured TTL.
  static Future<bool> hasValidCachedKey() async {
    final enabled = await isBiometricsEnabled();
    if (!enabled) return false;

    final cachedHex = await SecureStorage.instance.readString(keyCachedVaultKey);
    if (cachedHex == null || cachedHex.isEmpty) return false;

    final tsStr = await SecureStorage.instance.readString(keyCachedTimestamp);
    if (tsStr == null) return false;
    final timestamp = int.tryParse(tsStr);
    if (timestamp == null) return false;

    final ttl = await getAutoLockTtlSeconds();
    if (ttl > 0) {
      final elapsedSec = (DateTime.now().millisecondsSinceEpoch - timestamp) ~/ 1000;
      if (elapsedSec > ttl) {
        await purgeCachedKey();
        return false;
      }
    }
    return true;
  }

  /// Prompts OS biometric authentication challenge and unseals the cached Vault Key.
  ///
  /// Returns the raw 32-byte Vault Key if authentication succeeds and cached key is valid.
  /// Returns `null` if authentication fails, is canceled, or key is expired/absent.
  static Future<List<int>?> authenticateAndGetVaultKey() async {
    final hasKey = await hasValidCachedKey();
    if (!hasKey) return null;

    try {
      final label = await getBiometricLabel();
      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate with $label to unlock your SentinelVault',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!authenticated) return null;

      final hexKey = await SecureStorage.instance.readString(keyCachedVaultKey);
      if (hexKey == null || hexKey.isEmpty) return null;

      final List<int> keyBytes = [];
      for (int i = 0; i < hexKey.length; i += 2) {
        keyBytes.add(int.parse(hexKey.substring(i, i + 2), radix: 16));
      }
      return keyBytes;
    } catch (_) {
      return null;
    }
  }

  /// Immediately purges and invalidates the cached Vault Key from platform secure storage.
  /// Called on explicit lock, settings disable, or TTL expiration.
  static Future<void> purgeCachedKey() async {
    try {
      await SecureStorage.instance.deleteString(keyCachedVaultKey);
    } catch (_) {}
    try {
      await SecureStorage.instance.deleteString(keyCachedTimestamp);
    } catch (_) {}
  }
}
