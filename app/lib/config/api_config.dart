/// Configuration class providing base URLs for backend microservices.
///
/// **Production default (Docker/nginx):** all four base URLs return `''`
/// (empty string), so every API call becomes a same-origin relative path
/// (e.g. `/auth/register`, `/sync/pull`).  The nginx reverse-proxy routes
/// each path to the correct upstream container.
///
/// **Self-hosted / local-dev override:** set [customServerUrl] at runtime
/// (e.g. `'https://vault.mycompany.com'`).  If the URL is host-only (no
/// explicit port or path), per-service ports are appended automatically.
abstract class ApiConfig {
  // Compile-time overrides — only needed when running Flutter directly
  // outside Docker and hitting raw microservice ports.  The Dockerfile no
  // longer passes these; they default to '' (same-origin).
  static const String _defaultAuth = String.fromEnvironment('AUTH_BASE_URL', defaultValue: '');
  static const String _defaultSync = String.fromEnvironment('SYNC_BASE_URL', defaultValue: '');
  static const String _defaultSecurity = String.fromEnvironment('SECURITY_BASE_URL', defaultValue: '');
  static const String _defaultSharing = String.fromEnvironment('SHARING_BASE_URL', defaultValue: '');

  /// Runtime custom self-hosted server base URL override (e.g. 'https://vault.mycompany.com').
  static String? customServerUrl;

  /// Returns the active `auth-service` base URL.
  static String get authBaseUrl => _getUrl(customServerUrl, 3001, '/auth', _defaultAuth);

  /// Returns the active `sync-api` base URL.
  static String get syncBaseUrl => _getUrl(customServerUrl, 3002, '/sync', _defaultSync);

  /// Returns the active `security-analysis-service` base URL.
  static String get securityBaseUrl => _getUrl(customServerUrl, 3003, '/security', _defaultSecurity);

  /// Returns the active `sharing-service` base URL.
  static String get sharingBaseUrl => _getUrl(customServerUrl, 3004, '/sharing', _defaultSharing);

  static String _getUrl(String? custom, int port, String pathSegment, String defaultUrl) {
    if (custom == null || custom.trim().isEmpty) return defaultUrl;
    var base = custom.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);

    if (base.contains(':3001') || base.contains(':3002') || base.contains(':3003') || base.contains(':3004')) {
      return base;
    }

    if (base.contains('/auth') || base.contains('/sync') || base.contains('/security') || base.contains('/sharing')) {
      return base;
    }

    return '$base:$port';
  }
}
