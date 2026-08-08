import '../platform/secure_storage.dart';
import '../platform/duress_wipe_hook.dart';

/// Manages the state of local vault locks, in-memory cryptographic keys per vault,
/// and active backend authentication session.
///
/// Security Invariants:
/// 1. The Account Password and Master Password are completely separate.
/// 2. The Master Passwords (and keys derived from them) never leave the device.
/// 3. Each vault key is kept in memory independently and wiped immediately upon lock or logout.
class VaultLockManager {
  /// The global singleton instance of the vault lock manager.
  static final VaultLockManager instance = VaultLockManager._internal();

  /// Optional listener triggered when the vault lock state changes (lock/logout/unlock).
  void Function(bool isLocked)? onLockStateChanged;

  String? _sessionToken;
  /// Currently selected active vault ID.
  String? activeVaultId;

  // Key storage mapped by vaultId -> key bytes
  final Map<String, List<int>> _activeMasterKeys = {};
  final Map<String, List<int>> _activeVaultKeys = {};

  /// Indicates whether the user has toggled biometric quick-unlock in their settings.
  bool isBiometricEnabled = false;
  bool _hasBiometricCache = false;

  VaultLockManager._internal();

  bool _isDuressMode = false;

  /// The active backend session JWT token, or null if logged out.
  String? get sessionToken => _sessionToken;

  /// Active vault's master key, or null if active vault is locked.
  List<int>? get masterKey => activeVaultId != null ? _activeMasterKeys[activeVaultId!] : null;

  /// Active vault's vault key, or null if active vault is locked.
  List<int>? get vaultKey => activeVaultId != null ? _activeVaultKeys[activeVaultId!] : null;

  /// Returns true if the active vault is currently locked.
  bool get isLocked => vaultKey == null;

  /// Returns true if a specific [vaultId] is unlocked.
  bool isVaultUnlocked(String vaultId) => _activeVaultKeys.containsKey(vaultId);

  /// Retrieves the 32-byte Vault Key for a specific [vaultId], or null if locked.
  List<int>? getVaultKeyForId(String vaultId) => _activeVaultKeys[vaultId];

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

  /// Unlocks a single default/active vault by loading [masterKey] and [vaultKey] into memory.
  void unlock(List<int> masterKey, List<int> vaultKey, {bool isDuress = false}) {
    const defaultId = 'default';
    unlockVault(defaultId, masterKey, vaultKey, isDuress: isDuress);
  }

  /// Unlocks a specific [vaultId] by storing its derived [masterKey] and [vaultKey] in memory.
  void unlockVault(String vaultId, List<int> masterKey, List<int> vaultKey, {bool isDuress = false}) {
    _activeMasterKeys[vaultId] = List<int>.from(masterKey);
    _activeVaultKeys[vaultId] = List<int>.from(vaultKey);
    activeVaultId = vaultId;
    _isDuressMode = isDuress;
    if (isDuress) {
      triggerDuressWipeHook();
    }
    onLockStateChanged?.call(false);
  }

  /// Unlocks a vault directly using recovery key bytes.
  void unlockWithRecoveryKey(List<int> vaultKey, {String vaultId = 'default'}) {
    _activeVaultKeys[vaultId] = List<int>.from(vaultKey);
    activeVaultId = vaultId;
    onLockStateChanged?.call(false);
  }

  /// Locks a specific [vaultId] by zero-filling and purging its in-memory keys.
  void lockVault(String vaultId) {
    if (_activeMasterKeys.containsKey(vaultId)) {
      final key = _activeMasterKeys[vaultId]!;
      for (var i = 0; i < key.length; i++) {
        key[i] = 0;
      }
      _activeMasterKeys.remove(vaultId);
    }
    if (_activeVaultKeys.containsKey(vaultId)) {
      final key = _activeVaultKeys[vaultId]!;
      for (var i = 0; i < key.length; i++) {
        key[i] = 0;
      }
      _activeVaultKeys.remove(vaultId);
    }
    if (activeVaultId == vaultId) {
      activeVaultId = _activeVaultKeys.keys.firstOrNull;
    }
    onLockStateChanged?.call(_activeVaultKeys.isEmpty);
  }

  /// Locks all open vaults and clears all keys from memory.
  void lock() {
    lockAll();
  }

  /// Clears all unlocked vault keys from memory.
  void lockAll() {
    for (final key in _activeMasterKeys.values) {
      for (var i = 0; i < key.length; i++) {
        key[i] = 0;
      }
    }
    for (final key in _activeVaultKeys.values) {
      for (var i = 0; i < key.length; i++) {
        key[i] = 0;
      }
    }
    _activeMasterKeys.clear();
    _activeVaultKeys.clear();
    activeVaultId = null;
    _isDuressMode = false;
    onLockStateChanged?.call(true);
  }

  /// Logs out the user completely.
  void logout() {
    _sessionToken = null;
    SecureStorage.instance.deleteSessionToken();
    isBiometricEnabled = false;
    _clearBiometricCache();
    lockAll();
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
        unlock(keys['masterKey']!, keys['vaultKey']!);
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
        // ignore: avoid_catches_without_on_clauses
        .catchError((_) {});
  }
}
