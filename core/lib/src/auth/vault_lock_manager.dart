class VaultLockManager {
  static final VaultLockManager instance = VaultLockManager._internal();

  String? _sessionToken;
  List<int>? _masterKey;
  List<int>? _vaultKey;

  bool isBiometricEnabled = false;
  List<int>? _biometricWrappedMasterKey;
  List<int>? _biometricWrappedVaultKey;
  List<int>? _biometricPlatformKey; // Platform-gated hardware key simulator

  VaultLockManager._internal();

  String? get sessionToken => _sessionToken;
  List<int>? get masterKey => _masterKey;
  List<int>? get vaultKey => _vaultKey;

  bool get isLocked => _vaultKey == null;
  bool get isLoggedIn => _sessionToken != null;

  void setSession(String token) {
    _sessionToken = token;
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

  /// Caches the keys wrapped by a simulated biometric platform key.
  void enableBiometrics(List<int> masterKey, List<int> vaultKey) {
    isBiometricEnabled = true;
    _biometricPlatformKey = List<int>.generate(32, (i) => i * 3 + 7);
    _biometricWrappedMasterKey = _encryptSimple(masterKey, _biometricPlatformKey!);
    _biometricWrappedVaultKey = _encryptSimple(vaultKey, _biometricPlatformKey!);
  }

  /// Resets biometric state and cache.
  void disableBiometrics() {
    isBiometricEnabled = false;
    _clearBiometricCache();
  }

  bool get hasBiometricCache => _biometricWrappedVaultKey != null;

  /// Attempts to restore keys from biometric cache if authentication check [authSuccess] is true.
  bool unlockWithBiometrics(bool authSuccess) {
    if (!isBiometricEnabled || _biometricWrappedVaultKey == null || _biometricPlatformKey == null) {
      return false;
    }
    if (!authSuccess) {
      return false;
    }
    _masterKey = _decryptSimple(_biometricWrappedMasterKey!, _biometricPlatformKey!);
    _vaultKey = _decryptSimple(_biometricWrappedVaultKey!, _biometricPlatformKey!);
    return true;
  }

  /// Force invalidates the biometric cache (e.g. on enrollment changes).
  void invalidateBiometricCache() {
    _clearBiometricCache();
  }

  void _clearBiometricCache() {
    if (_biometricWrappedMasterKey != null) {
      for (var i = 0; i < _biometricWrappedMasterKey!.length; i++) {
        _biometricWrappedMasterKey![i] = 0;
      }
      _biometricWrappedMasterKey = null;
    }
    if (_biometricWrappedVaultKey != null) {
      for (var i = 0; i < _biometricWrappedVaultKey!.length; i++) {
        _biometricWrappedVaultKey![i] = 0;
      }
      _biometricWrappedVaultKey = null;
    }
    if (_biometricPlatformKey != null) {
      for (var i = 0; i < _biometricPlatformKey!.length; i++) {
        _biometricPlatformKey![i] = 0;
      }
      _biometricPlatformKey = null;
    }
  }

  List<int> _encryptSimple(List<int> plaintext, List<int> key) {
    final result = List<int>.filled(plaintext.length, 0);
    for (var i = 0; i < plaintext.length; i++) {
      result[i] = plaintext[i] ^ key[i % key.length];
    }
    return result;
  }

  List<int> _decryptSimple(List<int> ciphertext, List<int> key) {
    return _encryptSimple(ciphertext, key);
  }
}
