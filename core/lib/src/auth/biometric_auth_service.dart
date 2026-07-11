import '../platform/secure_storage.dart';

abstract class BiometricAuthService {
  static final BiometricAuthService instance = _DefaultBiometricAuthService();

  Future<bool> isBiometricsSupported();
  Future<bool> authenticate();
  Future<bool> wasEnrollmentChanged();
  void resetEnrollmentStatus();
  
  void setMockSupported(bool supported);
  void setMockAuthenticateSuccess(bool success);
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
