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
  bool _isSupported = true;
  bool _authSuccess = true;
  bool _enrollmentChanged = false;

  @override
  Future<bool> isBiometricsSupported() async => _isSupported;

  @override
  Future<bool> authenticate() async => _authSuccess;

  @override
  Future<bool> wasEnrollmentChanged() async => _enrollmentChanged;

  @override
  void resetEnrollmentStatus() {
    _enrollmentChanged = false;
  }

  @override
  void setMockSupported(bool supported) {
    _isSupported = supported;
  }

  @override
  void setMockAuthenticateSuccess(bool success) {
    _authSuccess = success;
  }

  @override
  void setMockEnrollmentChanged(bool changed) {
    _enrollmentChanged = changed;
  }
}
