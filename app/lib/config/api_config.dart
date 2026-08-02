abstract class ApiConfig {
  static const authBaseUrl = String.fromEnvironment('AUTH_BASE_URL', defaultValue: 'http://localhost:3001');
  static const syncBaseUrl = String.fromEnvironment('SYNC_BASE_URL', defaultValue: 'http://localhost:3002');
  static const securityBaseUrl = String.fromEnvironment('SECURITY_BASE_URL', defaultValue: 'http://localhost:3003');
  static const sharingBaseUrl = String.fromEnvironment('SHARING_BASE_URL', defaultValue: 'http://localhost:3004');
}
