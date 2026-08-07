import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Manages biometric-gated vault key caching in platform secure hardware storage
/// (iOS Keychain, Android Keystore, Windows Credential Manager / DPAPI).
///
/// Security Guarantees:
/// 1. Master Password is NEVER cached or stored anywhere.
/// 2. Only the derived 32-byte Vault Key is sealed in platform secure storage.
/// 3. Key unsealing requires passing OS biometric prompt via [local_auth].
/// 4. Disabling biometrics or explicit locking immediately purges all cached key material.
class BiometricVaultManager {
  static const _storage = FlutterSecureStorage();
  static final _auth = LocalAuthentication();

  static const String keyCachedVaultKey = 'sentinel_cached_vault_key';
  static const String keyCachedTimestamp = 'sentinel_vault_key_cached_at';
  static const String keyBiometricsEnabled = 'sentinel_biometrics_enabled';
  static const String keyAutoLockTtlSeconds = 'sentinel_auto_lock_ttl_seconds';

  /// Default inactivity TTL: 15 minutes (900 seconds)
  static const int defaultTtlSeconds = 900;

  /// Checks if hardware biometric authentication is available on the device.
  static Future<bool> isBiometricAvailable() async {
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
  static Future<bool> isBiometricsEnabled() async {
    final val = await _storage.read(key: keyBiometricsEnabled);
    return val == 'true';
  }

  /// Sets the biometric unlock setting state.
  /// If disabled, immediately purges any cached Vault Key from secure storage.
  static Future<void> setBiometricsEnabled(bool enabled) async {
    await _storage.write(key: keyBiometricsEnabled, value: enabled ? 'true' : 'false');
    if (!enabled) {
      await purgeCachedKey();
    }
  }

  /// Gets the configured auto-lock TTL in seconds.
  static Future<int> getAutoLockTtlSeconds() async {
    final val = await _storage.read(key: keyAutoLockTtlSeconds);
    if (val != null) {
      final parsed = int.tryParse(val);
      if (parsed != null) return parsed;
    }
    return defaultTtlSeconds;
  }

  /// Sets the auto-lock TTL in seconds.
  static Future<void> setAutoLockTtlSeconds(int seconds) async {
    await _storage.write(key: keyAutoLockTtlSeconds, value: seconds.toString());
  }

  /// Seals the 32-byte derived Vault Key inside platform secure hardware storage.
  ///
  /// [vaultKey] must be the raw 32-byte key array. The Master Password is NEVER passed here.
  static Future<void> cacheVaultKey(List<int> vaultKey) async {
    final enabled = await isBiometricsEnabled();
    if (!enabled) return;

    final hexKey = vaultKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: keyCachedVaultKey, value: hexKey);
    await _storage.write(key: keyCachedTimestamp, value: DateTime.now().millisecondsSinceEpoch.toString());
  }

  /// Checks if a valid cached Vault Key exists and has not expired past configured TTL.
  static Future<bool> hasValidCachedKey() async {
    final enabled = await isBiometricsEnabled();
    if (!enabled) return false;

    final cachedHex = await _storage.read(key: keyCachedVaultKey);
    if (cachedHex == null || cachedHex.isEmpty) return false;

    final tsStr = await _storage.read(key: keyCachedTimestamp);
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

      final hexKey = await _storage.read(key: keyCachedVaultKey);
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
      await _storage.delete(key: keyCachedVaultKey);
    } catch (_) {}
    try {
      await _storage.delete(key: keyCachedTimestamp);
    } catch (_) {}
  }
}
