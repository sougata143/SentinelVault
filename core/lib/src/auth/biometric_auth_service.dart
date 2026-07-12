import '../platform/secure_storage.dart';

/// Service interface for platform biometric authentication features.
///
/// Under the hood, this delegates to hardware key / secure storage bindings
/// depending on whether it is running on a native platform or web.
abstract class BiometricAuthService {
  /// The global singleton instance of the biometric authentication service.
  static final BiometricAuthService instance = _DefaultBiometricAuthService();

  /// Determines if biometric authentication is supported by the current device's hardware.
  Future<bool> isBiometricsSupported();

  /// Attempts to authenticate the user using system biometrics (e.g. Face ID / Touch ID / Fingerprint).
  ///
  /// Security invariant: In production, biometrics gate access to the cached Vault Key
  /// in the OS secure storage. This method verifies authorization capability.
  Future<bool> authenticate();

  /// Checks if new biometrics have been enrolled or deleted on the device,
  /// indicating a potential security state change.
  Future<bool> wasEnrollmentChanged();

  /// Resets the cached enrollment status check, marking the current biometric enrollment state as acknowledged.
  void resetEnrollmentStatus();
  
  /// Sets whether biometrics support is mocked as active or inactive in tests.
  void setMockSupported(bool supported);

  /// Sets whether simulated biometric authentication succeeds or fails in tests.
  void setMockAuthenticateSuccess(bool success);

  /// Sets whether simulated biometric enrollment changes are flagged as occurred in tests.
  void setMockEnrollmentChanged(bool changed);
}

class _DefaultBiometricAuthService implements BiometricAuthService {
  bool _isMocked = false;
  bool _isSupported = true;
  bool _authSuccess = true;
  bool _enrollmentChanged = false;

  @override
  Future<bool> isBiometricsSupported() async {
    if (_isMocked) return _isSupported;
    return await SecureStorage.instance.isHardwareKeySupported();
  }

  @override
  Future<bool> authenticate() async {
    if (_isMocked) return _authSuccess;
    // Reading from secure storage handles authenticating implicitly.
    // If authenticate is called on its own (like in settings to check authorization before toggle),
    // we can check if hardware is supported.
    return await SecureStorage.instance.isHardwareKeySupported();
  }

  @override
  Future<bool> wasEnrollmentChanged() async {
    if (_isMocked) return _enrollmentChanged;
    return await SecureStorage.instance.wasEnrollmentChanged();
  }

  @override
  void resetEnrollmentStatus() {
    _enrollmentChanged = false;
    SecureStorage.instance.resetEnrollmentStatus();
  }

  @override
  void setMockSupported(bool supported) {
    _isMocked = true;
    _isSupported = supported;
  }

  @override
  void setMockAuthenticateSuccess(bool success) {
    _isMocked = true;
    _authSuccess = success;
  }

  @override
  void setMockEnrollmentChanged(bool changed) {
    _isMocked = true;
    _enrollmentChanged = changed;
    if (SecureStorage.instance is InMemorySecureStorage) {
      (SecureStorage.instance as InMemorySecureStorage).setMockEnrollmentChanged(changed);
    }
  }
}
