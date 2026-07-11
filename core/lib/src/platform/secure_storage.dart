import 'dart:async';

/// Abstract interface for platform-specific secure storage.
/// 
/// Handles session token persistence and biometric-gated hardware key wrapping.
abstract class SecureStorage {
  /// The global active instance of platform secure storage.
  static SecureStorage instance = InMemorySecureStorage();

  /// Writes the account session token.
  Future<void> writeSessionToken(String token);

  /// Reads the account session token, or null if none is saved.
  Future<String?> readSessionToken();

  /// Deletes the account session token.
  Future<void> deleteSessionToken();

  /// Checks if hardware-backed secure storage (Secure Enclave / Keystore with StrongBox) is supported.
  Future<bool> isHardwareKeySupported();

  /// Encrypts and persists the Master Key and Vault Key under a hardware-backed biometric-required key.
  Future<void> writeBiometricWrappedVaultKey(List<int> masterKey, List<int> vaultKey);

  /// Prompts for biometrics to decrypt and return the cached keys.
  Future<Map<String, List<int>>?> readBiometricWrappedVaultKey();

  /// Deletes the biometric-cached keys.
  Future<void> deleteBiometricWrappedVaultKey();

  /// Checks if biometric enrollment or device passcode has changed.
  Future<bool> wasEnrollmentChanged();

  /// Resets the biometric configuration change detection status.
  Future<void> resetEnrollmentStatus();

  /// Writes a generic string value.
  Future<void> writeString(String key, String value);

  /// Reads a generic string value, or null if not found.
  Future<String?> readString(String key);

  /// Deletes a generic string value.
  Future<void> deleteString(String key);
}

/// Fallback in-memory implementation of [SecureStorage] used for tests.
class InMemorySecureStorage implements SecureStorage {
  String? _sessionToken;
  List<int>? _cachedMasterKey;
  List<int>? _cachedVaultKey;
  bool _mockEnrollmentChanged = false;

  @override
  Future<void> writeSessionToken(String token) async {
    _sessionToken = token;
  }

  @override
  Future<String?> readSessionToken() async {
    return _sessionToken;
  }

  @override
  Future<void> deleteSessionToken() async {
    _sessionToken = null;
  }

  @override
  Future<bool> isHardwareKeySupported() async {
    return true;
  }

  @override
  Future<void> writeBiometricWrappedVaultKey(List<int> masterKey, List<int> vaultKey) async {
    _cachedMasterKey = List<int>.from(masterKey);
    _cachedVaultKey = List<int>.from(vaultKey);
  }

  @override
  Future<Map<String, List<int>>?> readBiometricWrappedVaultKey() async {
    if (_cachedMasterKey == null || _cachedVaultKey == null) return null;
    return {
      'masterKey': _cachedMasterKey!,
      'vaultKey': _cachedVaultKey!,
    };
  }

  @override
  Future<void> deleteBiometricWrappedVaultKey() async {
    _cachedMasterKey = null;
    _cachedVaultKey = null;
  }

  @override
  Future<bool> wasEnrollmentChanged() async {
    return _mockEnrollmentChanged;
  }

  @override
  Future<void> resetEnrollmentStatus() async {
    _mockEnrollmentChanged = false;
  }

  /// Sets the mock enrollment change state for tests.
  void setMockEnrollmentChanged(bool changed) {
    _mockEnrollmentChanged = changed;
  }

  final Map<String, String> _mockStringStore = {};

  @override
  Future<void> writeString(String key, String value) async {
    _mockStringStore[key] = value;
  }

  @override
  Future<String?> readString(String key) async {
    return _mockStringStore[key];
  }

  @override
  Future<void> deleteString(String key) async {
    _mockStringStore.remove(key);
  }
}
