import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../theme/theme.dart';
import '../../../config/api_config.dart';

class SsoConfigDialog extends StatefulWidget {
  final String? teamVaultId;
  final String? sessionToken;
  final String? authBaseUrl;
  final http.Client? httpClient;

  const SsoConfigDialog({
    super.key,
    this.teamVaultId,
    this.sessionToken,
    this.authBaseUrl,
    this.httpClient,
  });

  @override
  State<SsoConfigDialog> createState() => _SsoConfigDialogState();
}

class _SsoConfigDialogState extends State<SsoConfigDialog> {
  final _domainController = TextEditingController();
  final _issuerUrlController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  String get _effectiveAuthBaseUrl =>
      (widget.authBaseUrl != null && widget.authBaseUrl!.isNotEmpty)
          ? widget.authBaseUrl!
          : ApiConfig.authBaseUrl;

  Future<void> _saveSsoConfig() async {
    final domain = _domainController.text.trim();
    final issuerUrl = _issuerUrlController.text.trim();
    final clientId = _clientIdController.text.trim();
    final clientSecret = _clientSecretController.text.trim();

    if (domain.isEmpty || issuerUrl.isEmpty || clientId.isEmpty) {
      setState(() => _errorMessage = 'Domain, Issuer URL, and Client ID are required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final client = widget.httpClient ?? http.Client();
      final uri = Uri.parse('$_effectiveAuthBaseUrl/auth/sso/config');

      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (widget.sessionToken != null) 'Authorization': 'Bearer ${widget.sessionToken}',
        },
        body: jsonEncode({
          'domain': domain,
          'issuerUrl': issuerUrl,
          'clientId': clientId,
          if (clientSecret.isNotEmpty) 'clientSecret': clientSecret,
          if (widget.teamVaultId != null) 'teamVaultId': widget.teamVaultId,
          'isEnabled': true,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SSO Configuration saved successfully!')),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to save SSO config (HTTP ${response.statusCode})';
          _isSaving = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving SSO config: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SentinelTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.corporate_fare, color: SentinelTheme.accentCyan),
          SizedBox(width: 8),
          Text('Team SSO Configuration', style: TextStyle(color: SentinelTheme.textPrimary, fontSize: 18)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Configure OpenID Connect (OIDC) Single Sign-On for your organization (Okta, Azure AD, Google Workspace).',
              style: TextStyle(color: SentinelTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _domainController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Enterprise Domain (e.g. acme.corp)',
                prefixText: '@',
                filled: true,
                fillColor: SentinelTheme.cardDark,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _issuerUrlController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'IdP Issuer URL (OIDC Discovery / Tenant URL)',
                filled: true,
                fillColor: SentinelTheme.cardDark,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientIdController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'OAuth2 Client ID',
                filled: true,
                fillColor: SentinelTheme.cardDark,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientSecretController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Client Secret (Optional if PKCE only)',
                filled: true,
                fillColor: SentinelTheme.cardDark,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: SentinelTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveSsoConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: SentinelTheme.accentCyan,
            foregroundColor: Colors.black,
          ),
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Save SSO Config'),
        ),
      ],
    );
  }
}
