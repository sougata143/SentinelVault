import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import '../../theme/theme.dart';
import '../../config/api_config.dart';

class SsoLoginButton extends StatefulWidget {
  final String email;
  final String? authBaseUrl;
  final http.Client? httpClient;
  final Function(String sessionToken, String email)? onSsoAuthenticated;

  const SsoLoginButton({
    super.key,
    required this.email,
    this.authBaseUrl,
    this.httpClient,
    this.onSsoAuthenticated,
  });

  @override
  State<SsoLoginButton> createState() => _SsoLoginButtonState();
}

class _SsoLoginButtonState extends State<SsoLoginButton> {
  bool _checkingDomain = false;
  bool _ssoAvailable = false;
  String? _ssoDomain;
  String? _errorMessage;

  String get _effectiveAuthBaseUrl =>
      (widget.authBaseUrl != null && widget.authBaseUrl!.isNotEmpty)
          ? widget.authBaseUrl!
          : ApiConfig.authBaseUrl;

  @override
  void didUpdateWidget(covariant SsoLoginButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email) {
      _checkDomainSso();
    }
  }

  Future<void> _checkDomainSso() async {
    final domain = SsoAuthHelper.extractDomainFromEmail(widget.email);
    if (domain == null) {
      setState(() {
        _ssoAvailable = false;
        _ssoDomain = null;
      });
      return;
    }

    setState(() => _checkingDomain = true);

    try {
      final client = widget.httpClient ?? http.Client();
      final uri = Uri.parse('$_effectiveAuthBaseUrl/auth/sso/config/$domain');
      final response = await client.get(uri);

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        setState(() {
          _ssoAvailable = resJson['ssoAvailable'] as bool? ?? false;
          _ssoDomain = domain;
          _checkingDomain = false;
        });
      } else {
        setState(() {
          _ssoAvailable = false;
          _checkingDomain = false;
        });
      }
    } catch (_) {
      setState(() {
        _ssoAvailable = false;
        _checkingDomain = false;
      });
    }
  }

  Future<void> _startSsoFlow() async {
    if (_ssoDomain == null) return;

    try {
      final crypto = VaultCrypto();
      final pkce = SsoAuthHelper.generatePkceChallenge(crypto);

      final client = widget.httpClient ?? http.Client();
      final initUri = Uri.parse('$_effectiveAuthBaseUrl/auth/sso/login-init');

      const redirectUri = 'https://sentinelvault.app/sso/callback';

      final initRes = await client.post(
        initUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'domain': _ssoDomain,
          'redirectUri': redirectUri,
          'codeChallenge': pkce.codeChallenge,
          'codeChallengeMethod': pkce.codeChallengeMethod,
        }),
      );

      if (initRes.statusCode == 200) {
        final initJson = jsonDecode(initRes.body);
        final state = initJson['state'] as String;

        // Simulate OIDC authorization callback exchange
        final callbackUri = Uri.parse('$_effectiveAuthBaseUrl/auth/sso/callback');
        final callbackRes = await client.post(
          callbackUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': 'oidc-auth-code-12345',
            'state': state,
            'codeVerifier': pkce.codeVerifier,
            'redirectUri': redirectUri,
          }),
        );

        if (callbackRes.statusCode == 200) {
          final cbJson = jsonDecode(callbackRes.body);
          final sessionToken = cbJson['sessionToken'] as String;
          final userEmail = cbJson['user']['email'] as String;

          // Set session token in LockManager -> Vault remains locked!
          VaultLockManager.instance.setSession(sessionToken);

          widget.onSsoAuthenticated?.call(sessionToken, userEmail);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🔒 SSO Identity Authenticated. Enter Master Password to unlock vault.'),
                backgroundColor: SentinelTheme.accentCyan,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'SSO Authentication failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingDomain) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: SentinelTheme.accentCyan)),
      );
    }

    if (!_ssoAvailable || _ssoDomain == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startSsoFlow,
            icon: const Icon(Icons.corporate_fare, size: 20),
            label: Text('Sign in with SSO ($_ssoDomain)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SentinelTheme.cardDark,
              foregroundColor: SentinelTheme.accentCyan,
              side: const BorderSide(color: SentinelTheme.accentCyan),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
      ],
    );
  }
}
