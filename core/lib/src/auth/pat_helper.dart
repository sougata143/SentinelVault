/// Utility helpers for Personal Access Tokens (PATs) in SentinelVault.
class PatHelper {
  /// Token prefix identifier for live production Personal Access Tokens.
  static const String patLivePrefix = 'pat_sv_live_';

  /// Validates whether a token string matches the SentinelVault PAT format.
  static bool isValidPatFormat(String token) {
    final trimmed = token.trim();
    if (!trimmed.startsWith(patLivePrefix)) {
      return false;
    }
    final secretPart = trimmed.substring(patLivePrefix.length);
    return secretPart.length == 32;
  }

  /// Extracts a safe display prefix for UI listings (e.g. `pat_sv_live_a1b2...`).
  static String extractDisplayPrefix(String token) {
    if (!isValidPatFormat(token)) {
      return 'pat_invalid...';
    }
    final secretPart = token.trim().substring(patLivePrefix.length);
    return '$patLivePrefix${secretPart.substring(0, 4)}...';
  }

  /// Returns true if [grantedScopes] contains [requiredScope] or admin wildcard.
  static bool hasScope({
    required String requiredScope,
    required List<String> grantedScopes,
  }) {
    if (grantedScopes.contains('admin:*')) return true;
    return grantedScopes.contains(requiredScope);
  }
}
