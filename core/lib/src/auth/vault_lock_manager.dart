import '../platform/secure_storage.dart';

class VaultLockManager {
  static final VaultLockManager instance = VaultLockManager._internal();

  String? _sessionToken;
  List<int>? _masterKey;
  List<int>? _vaultKey;

  bool isBiometricEnabled = false;
  bool _hasBiometricCache = false;

  VaultLockManager._internal();

  String? get sessionToken => _sessionToken;
  List<int>? get masterKey => _masterKey;
  List<int>? get vaultKey => _vaultKey;

  bool get isLocked => _vaultKey == null;
  bool get isLoggedIn => _sessionToken != null;

  /// Loads the persisted session token from secure storage.
  Future<void> loadSession() async {
    _sessionToken = await SecureStorage.instance.readSessionToken();
  }

  void setSession(String token) {
    _sessionToken = token;
    SecureStorage.instance.writeSessionToken(token);
  }

  void unlock(List<int> masterKey, List<int> vaultKey) {
    _masterKey = List<int>.from(masterKey);
    _vaultKey = List<int>.from(vaultKey);
  }

  void unlockWithRecoveryKey(List<int> vaultKey) {
    _masterKey = null;
    _vaultKey = List<int>.from(vaultKey);
  }

  /// Locks the vault.
  /// Clears the Master Key and Vault Key from memory, but keeps the account session valid.
  void lock() {
    if (_masterKey != null) {
      for (var i = 0; i < _masterKey!.length; i++) {
        _masterKey![i] = 0;
      }
      _masterKey = null;
    }
    if (_vaultKey != null) {
      for (var i = 0; i < _vaultKey!.length; i++) {
        _vaultKey![i] = 0;
      }
      _vaultKey = null;
    }
  }

  /// Logs out the user.
  /// Clears the session token, biometric settings, and performs key clearance.
  void logout() {
    _sessionToken = null;
    SecureStorage.instance.deleteSessionToken();
    isBiometricEnabled = false;
    _clearBiometricCache();
    if (_masterKey != null) {
      for (var i = 0; i < _masterKey!.length; i++) {
        _masterKey![i] = 0;
      }
      _masterKey = null;
    }
    if (_vaultKey != null) {
      for (var i = 0; i < _vaultKey!.length; i++) {
        _vaultKey![i] = 0;
      }
      _vaultKey = null;
    }
  }

  /// Caches the keys wrapped by a biometric-gated hardware key.
  Future<void> enableBiometrics(List<int> masterKey, List<int> vaultKey) async {
    isBiometricEnabled = true;
    _hasBiometricCache = true;
    await SecureStorage.instance.writeBiometricWrappedVaultKey(masterKey, vaultKey);
  }

  /// Resets biometric state and cache.
  void disableBiometrics() {
    isBiometricEnabled = false;
    _clearBiometricCache();
  }

  bool get hasBiometricCache => _hasBiometricCache;

  /// Attempts to restore keys from biometric cache if authentication check [authSuccess] is true.
  Future<bool> unlockWithBiometrics(bool authSuccess) async {
    if (!isBiometricEnabled || !_hasBiometricCache) {
      return false;
    }
    if (!authSuccess) {
      return false;
    }
    try {
      final keys = await SecureStorage.instance.readBiometricWrappedVaultKey();
      if (keys != null) {
        _masterKey = keys['masterKey'];
        _vaultKey = keys['vaultKey'];
        return true;
      }
    } catch (e) {
      invalidateBiometricCache();
    }
    return false;
  }

  /// Force invalidates the biometric cache (e.g. on enrollment changes).
  void invalidateBiometricCache() {
    _clearBiometricCache();
  }

  void _clearBiometricCache() {
    _hasBiometricCache = false;
    SecureStorage.instance.deleteBiometricWrappedVaultKey();
  }
}
