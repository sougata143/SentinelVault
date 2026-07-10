import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class MasterPasswordSetupScreen extends StatefulWidget {
  final String email;

  const MasterPasswordSetupScreen({
    super.key,
    required this.email,
  });

  @override
  State<MasterPasswordSetupScreen> createState() => _MasterPasswordSetupScreenState();
}

class _MasterPasswordSetupScreenState extends State<MasterPasswordSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _masterPasswordController = TextEditingController();
  final _confirmMasterPasswordController = TextEditingController();

  @override
  void dispose() {
    _masterPasswordController.dispose();
    _confirmMasterPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              color: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.vpn_key_outlined,
                        color: AppTheme.primaryColor,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Create Master Password',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'This is different from your account password and is never sent to our servers. If you forget it, we cannot recover your vault.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('master-password-field'),
                        controller: _masterPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Master Password',
                          prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondaryColor),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('confirm-master-password-field'),
                        controller: _confirmMasterPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm Master Password',
                          prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondaryColor),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('create-master-button'),
                        onPressed: () {
                          // Will be fully implemented in the next phase
                        },
                        child: const Text('Create & Unlock Vault'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
