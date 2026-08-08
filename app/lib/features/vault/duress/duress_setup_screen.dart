import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../../theme/theme.dart';

class DuressSetupScreen extends StatefulWidget {
  final VaultDatabase? database;

  const DuressSetupScreen({
    super.key,
    this.database,
  });

  @override
  State<DuressSetupScreen> createState() => _DuressSetupScreenState();
}

class _DuressSetupScreenState extends State<DuressSetupScreen> {
  final _duressPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _prepopulateItems = true;
  bool _isSaving = false;
  bool _isConfigured = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkConfiguredStatus();
  }

  Future<void> _checkConfiguredStatus() async {
    final isConfigured = await DualVaultManager.instance.isDecoyConfigured();
    setState(() => _isConfigured = isConfigured);
  }

  Future<void> _setupDuressVault() async {
    final password = _duressPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (password.length < 8) {
      setState(() => _errorMessage = 'Duress Password must be at least 8 characters.');
      return;
    }

    if (password != confirm) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final crypto = VaultCrypto();

      // 1. Initialize Decoy Vault keys and salt
      final result = await DualVaultManager.instance.setupDecoyVault(
        duressPassword: password,
        crypto: crypto,
      );

      // 2. Pre-populate sample decoy items if DB is provided
      if (_prepopulateItems && widget.database != null) {
        await DualVaultManager.instance.prepopulateDecoyItems(
          widget.database!,
          result.decoyVaultKey,
        );
      }

      setState(() {
        _isSaving = false;
        _isConfigured = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔒 Duress / Decoy Vault configured successfully!'),
            backgroundColor: SentinelTheme.accentCyan,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error configuring decoy vault: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SentinelTheme.backgroundDark,
      appBar: AppBar(
        title: const Text('Duress / Decoy Vault Setup'),
        backgroundColor: SentinelTheme.surfaceDark,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Safety & Limitation Notice Banner (Rule 14 Compliance)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SentinelTheme.warningYellow.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SentinelTheme.warningYellow.withOpacity(0.5)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_moon_outlined, color: SentinelTheme.warningYellow, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Entering your Duress Password under coercion unlocks a plausible Decoy Vault and purges biometric quick-unlock caches for your real vault. Note: This provides on-screen plausible deniability, but does not modify your real vault\'s encrypted local database.',
                      style: TextStyle(color: SentinelTheme.textPrimary, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_isConfigured) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SentinelTheme.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SentinelTheme.accentCyan),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: SentinelTheme.accentCyan),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Decoy Vault Status: Active & Protected',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            const Text(
              'Configure Duress Master Password',
              style: TextStyle(color: SentinelTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _duressPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Alternate Duress Master Password',
                filled: true,
                fillColor: SentinelTheme.cardDark,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Confirm Alternate Password',
                filled: true,
                fillColor: SentinelTheme.cardDark,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: SentinelTheme.accentCyan,
              title: const Text('Pre-populate Harmless Fake Entries', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Populates decoy vault with plausible sample passwords (Google account, shopping card, to-do list).', style: TextStyle(color: SentinelTheme.textMuted, fontSize: 12)),
              value: _prepopulateItems,
              onChanged: (val) => setState(() => _prepopulateItems = val),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _setupDuressVault,
                icon: const Icon(Icons.security, size: 20),
                label: Text(_isConfigured ? 'Update Duress Vault' : 'Enable Duress / Decoy Vault'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SentinelTheme.accentCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
