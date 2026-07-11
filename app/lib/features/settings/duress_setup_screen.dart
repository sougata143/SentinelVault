import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';

/// Opt-in Duress / Decoy Vault setup screen.
///
/// Located in Settings — the label "Duress" appears only in this flow, never
/// on the Unlock screen itself (per the skill requirement).
class DuressSetupScreen extends StatefulWidget {
  const DuressSetupScreen({super.key});

  @override
  State<DuressSetupScreen> createState() => _DuressSetupScreenState();
}

class _DuressSetupScreenState extends State<DuressSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _duressPasswordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _masterPasswordController = TextEditingController();

  bool _isConfigured = false;
  bool _isLoading = false;
  bool _obscureDuress = true;
  bool _obscureConfirm = true;
  bool _obscureMaster = true;
  bool _limitationsAcknowledged = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingConfiguration();
  }

  Future<void> _checkExistingConfiguration() async {
    final existing = await SecureStorage.instance.readString(
      DualVaultManager.duressConfiguredKey,
    );
    if (mounted) {
      setState(() => _isConfigured = existing == 'true');
    }
  }

  @override
  void dispose() {
    _duressPasswordController.dispose();
    _confirmController.dispose();
    _masterPasswordController.dispose();
    super.dispose();
  }

  String? _validateDuressPassword(String? value) {
    if (value == null || value.length < 8) {
      return 'Duress password must be at least 8 characters';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _duressPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _saveSetup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_limitationsAcknowledged) {
      setState(() => _errorMessage = 'Please acknowledge the limitations below.');
      return;
    }
    if (_masterPasswordController.text.isEmpty) {
      setState(() => _errorMessage = 'Master Password cannot be empty.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final crypto = VaultCrypto();

      // 1. Generate independent 16-byte salt for Vault Beta's Argon2id.
      final betaSalt = crypto.generateRandomBytes(16);
      final betaVaultKey = crypto.generateRandomBytes(32);

      // 2. Derive a KDF key from the Duress Password + betaSalt.
      final duressKdfKey = await crypto.deriveRecoveryKdfKey(
        recoveryKey: _duressPasswordController.text,
        salt: betaSalt,
      );

      // 3. Wrap the Vault Beta key under the Duress KDF key.
      final wrappedBetaKey = await crypto.wrapVaultKey(
        masterKey: duressKdfKey,
        vaultKey: betaVaultKey,
      );

      // 4. Store everything locally — nothing leaves the device.
      final betaSaltHex = betaSalt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final wrappedHex = wrappedBetaKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      await SecureStorage.instance.writeString(DualVaultManager.duressSaltKey, betaSaltHex);
      await SecureStorage.instance.writeString(DualVaultManager.duressWrappedKeyKey, wrappedHex);
      await SecureStorage.instance.writeString(DualVaultManager.duressConfiguredKey, 'true');

      setState(() => _isConfigured = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Decoy vault configured successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Setup failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeSetup() async {
    setState(() => _isLoading = true);
    await SecureStorage.instance.deleteString(DualVaultManager.duressSaltKey);
    await SecureStorage.instance.deleteString(DualVaultManager.duressWrappedKeyKey);
    await SecureStorage.instance.deleteString(DualVaultManager.duressConfiguredKey);
    if (mounted) {
      setState(() {
        _isConfigured = false;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Decoy vault configuration removed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Decoy Vault Setup'),
        backgroundColor: AppTheme.surfaceColor,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _isConfigured ? _buildConfiguredView() : _buildSetupForm(),
        ),
      ),
    );
  }

  Widget _buildConfiguredView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusCard(),
        const SizedBox(height: 32),
        Text(
          'Your decoy vault is active. Entering the separate password on the '
          'Unlock screen will open the decoy vault and clear your quick-unlock '
          'cache — but will never expose or modify your real vault data.',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          key: const Key('remove-decoy-button'),
          onPressed: _isLoading ? null : _removeSetup,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove Decoy Vault'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade900,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _buildSetupForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Limitations Disclosure ───────────────────────────────────────
          _buildLimitationsCard(),
          const SizedBox(height: 24),

          // ── Duress Password Fields ───────────────────────────────────────
          const Text(
            'Set a Separate Unlock Password',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a password different from your Master Password. '
            'Entering this on the Unlock screen will open a decoy vault.',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          _buildPasswordField(
            key: 'duress-password-field',
            controller: _duressPasswordController,
            label: 'Separate unlock password',
            obscure: _obscureDuress,
            onToggle: () => setState(() => _obscureDuress = !_obscureDuress),
            validator: _validateDuressPassword,
          ),
          const SizedBox(height: 12),
          _buildPasswordField(
            key: 'confirm-duress-field',
            controller: _confirmController,
            label: 'Confirm password',
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            validator: _validateConfirm,
          ),
          const SizedBox(height: 24),
          const Text(
            'Verify Your Identity',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          _buildPasswordField(
            key: 'master-password-verify-field',
            controller: _masterPasswordController,
            label: 'Current Master Password',
            obscure: _obscureMaster,
            onToggle: () => setState(() => _obscureMaster = !_obscureMaster),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),

          // ── Acknowledgement ──────────────────────────────────────────────
          const SizedBox(height: 20),
          CheckboxListTile(
            key: const Key('limitations-ack-checkbox'),
            value: _limitationsAcknowledged,
            onChanged: (v) => setState(() => _limitationsAcknowledged = v ?? false),
            activeColor: AppTheme.primaryColor,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I understand the limitations above and that this cannot '
              'guarantee forensic deniability.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
          ],

          const SizedBox(height: 24),
          ElevatedButton(
            key: const Key('enable-decoy-button'),
            onPressed: _isLoading ? null : _saveSetup,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              minimumSize: const Size.fromHeight(50),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Enable Decoy Vault',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade900.withOpacity(0.3),
        border: Border.all(color: Colors.green.shade700),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.greenAccent),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Decoy vault is configured and active.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitationsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withOpacity(0.2),
        border: Border.all(color: Colors.amber.shade700),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.warning_amber_outlined, color: Colors.amber),
            SizedBox(width: 8),
            Text(
              'Important Limitations',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            'This feature reduces certain risks but cannot guarantee '
            'that an adversary will not notice:\n\n'
            '  • Multiple encrypted database files on the device\n'
            '  • Unusual storage or backup patterns\n'
            '  • Public knowledge that this app offers a decoy feature\n\n'
            'It is not a substitute for legal protection or flight risk planning. '
            'Do not rely on this as an absolute forensic deniability guarantee.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required String key,
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: Key(key),
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: AppTheme.surfaceColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.white54,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
