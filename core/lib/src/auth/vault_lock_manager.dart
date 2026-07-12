import '../platform/secure_storage.dart';

/// Manages the state of the local vault lock, in-memory cryptographic keys,
/// and active backend authentication session.
///
/// Security Invariants:
/// 1. The Account Password and Master Password are completely separate.
/// 2. The Master Password (and keys derived from it) never leaves the device.
/// 3. In-memory keys (masterKey, vaultKey) are wiped immediately upon lock or logout.
class VaultLockManager {
  /// The global singleton instance of the vault lock manager.
  static final VaultLockManager instance = VaultLockManager._internal();

  String? _sessionToken;
  List<int>? _masterKey;
  List<int>? _vaultKey;

  /// Indicates whether the user has toggled biometric quick-unlock in their settings.
  bool isBiometricEnabled = false;
  bool _hasBiometricCache = false;

  VaultLockManager._internal();

  bool _isDuressMode = false;

  /// The active backend session JWT token, or null if logged out.
  String? get sessionToken => _sessionToken;

  /// The derived master key used for SRP authentication, or null if locked.
  List<int>? get masterKey => _masterKey;

  /// The vault encryption/decryption key, or null if locked.
  List<int>? get vaultKey => _vaultKey;

  /// Returns true if the vault is currently locked (i.e. vault key is not in memory).
  bool get isLocked => _vaultKey == null;

  /// Returns true if the user is authenticated with the backend (has an active session token).
  bool get isLoggedIn => _sessionToken != null;

  /// Returns true if the vault was unlocked using a decoy/duress password.
  bool get isDuressMode => _isDuressMode;

  /// Loads the persisted session token from secure storage.
  Future<void> loadSession() async {
    _sessionToken = await SecureStorage.instance.readSessionToken();
  }

  /// Sets the active backend session [token] and persists it to secure storage.
  void setSession(String token) {
    _sessionToken = token;
    SecureStorage.instance.writeSessionToken(token);
  }

  /// Unlocks the vault by loading the derived [masterKey] and [vaultKey] into memory.
  ///
  /// Set [isDuress] to true if unlocked via the decoy password.
  void unlock(List<int> masterKey, List<int> vaultKey, {bool isDuress = false}) {
    _masterKey = List<int>.from(masterKey);
    _vaultKey = List<int>.from(vaultKey);
    _isDuressMode = isDuress;
  }

  /// Unlocks the vault directly using the recovery key's derived [vaultKey] (bypasses Master Password derivation).
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
    _isDuressMode = false;
  }

  /// Logs out the user.
  /// Clears the session token, biometric settings, and performs key clearance.
  void logout() {
    _sessionToken = null;
    SecureStorage.instance.deleteSessionToken();
    isBiometricEnabled = false;
    _clearBiometricCache();
    _isDuressMode = false;
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

  /// Returns true if a wrapped copy of the vault keys is cached in secure storage.
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
    SecureStorage.instance.deleteBiometricWrappedVaultKey()
        // The failure is already logged + rethrown inside deleteBiometricWrappedVaultKey.
        // Catch here so the unawaited fire-and-forget call cannot surface as an
        // unhandled async exception and crash the app.
        // ignore: avoid_catches_without_on_clauses
        .catchError((_) {});
  }
}
