class VaultLockManager {
  static final VaultLockManager instance = VaultLockManager._internal();

  String? _sessionToken;
  List<int>? _masterKey;
  List<int>? _vaultKey;

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
  /// Clears the session token and performs key clearance.
  void logout() {
    _sessionToken = null;
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
}
