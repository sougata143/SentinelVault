import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import '../../theme/theme.dart';
import '../../app_shell.dart';

class MasterPasswordSetupScreen extends StatefulWidget {
  final String email;
  final String syncBaseUrl;
  final http.Client? httpClient;

  const MasterPasswordSetupScreen({
    super.key,
    required this.email,
    this.syncBaseUrl = 'http://localhost:3002',
    this.httpClient,
  });

  @override
  State<MasterPasswordSetupScreen> createState() => _MasterPasswordSetupScreenState();
}


class _MasterPasswordSetupScreenState extends State<MasterPasswordSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _masterPasswordController = TextEditingController();
  final _confirmMasterPasswordController = TextEditingController();
  String _passwordValue = '';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _masterPasswordController.addListener(() {
      setState(() {
        _passwordValue = _masterPasswordController.text;
      });
    });
  }

  @override
  void dispose() {
    _masterPasswordController.dispose();
    _confirmMasterPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateMasterPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final password = _masterPasswordController.text;

    try {
      final syncClient = HttpSyncApiClient(
        baseUrl: widget.syncBaseUrl,
        userId: widget.email,
        httpClient: widget.httpClient,
      );


      final crypto = VaultCrypto();
      // 1. Generate random KDF salt
      final salt = crypto.generateRandomBytes(16);

      // 2. Derive Master Key via Argon2id
      final masterKey = await crypto.deriveMasterKey(
        masterPassword: password,
        salt: salt,
      );

      // 3. Generate random 32-byte Vault Key
      final vaultKey = crypto.generateRandomBytes(32);

      // 4. Wrap Vault Key under Master Key using AES-256-GCM
      final wrappedVaultKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        masterKey: masterKey,
      );

      // Convert lists of bytes to hex strings for transmission
      final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final wrappedKeyHex = wrappedVaultKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // 5. Upload only salt and wrapped key (never the password or raw key)
      await syncClient.uploadVaultKey(
        saltHex: saltHex,
        wrappedKeyHex: wrappedKeyHex,
      );

      // 6. Open in-memory DB and navigate to the dashboard shell
      final db = SqliteVaultDatabase.inMemory();
      db.open(vaultKey);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AppShell(db: db, vaultKey: vaultKey),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to setup vault. Please try again.';
      });
    }

 finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppTheme.errorColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: const Key('master-password-field'),
                        controller: _masterPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Master Password',
                          prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondaryColor),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Master password is required';
                          }
                          if (value.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      PasswordStrengthMeter(
                        password: _passwordValue,
                        userInputs: [widget.email],
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
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your Master Password';
                          }
                          if (value != _masterPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('create-master-button'),
                        onPressed: _isLoading ? null : _handleCreateMasterPassword,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Create & Unlock Vault'),
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

class PasswordStrengthMeter extends StatelessWidget {
  final String password;
  final List<String> userInputs;

  const PasswordStrengthMeter({
    super.key,
    required this.password,
    required this.userInputs,
  });

  String _getScoreText(int score) {
    switch (score) {
      case 0:
        return 'Very Weak';
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Strong';
      case 4:
        return 'Very Strong';
      default:
        return 'Unknown';
    }
  }

  Color _getStrengthColor(int score) {
    switch (score) {
      case 0:
      case 1:
        return AppTheme.errorColor;
      case 2:
        return AppTheme.warningColor;
      case 3:
        return Colors.yellow;
      case 4:
        return AppTheme.primaryColor;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = PasswordAnalyzer.analyze(password, userInputs: userInputs);
    final score = result.score;
    final color = _getStrengthColor(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: List.generate(4, (index) {
            final isFilled = index < score;
            final barColor = isFilled ? color : Colors.white.withOpacity(0.1);
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                password.isEmpty ? 'No Password Entered' : 'Strength: ${_getScoreText(score)}',
                style: TextStyle(
                  color: password.isEmpty ? Colors.grey : color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (password.isNotEmpty)
              Flexible(
                child: Text(
                  'Crack time: ${result.estimatedCrackTime}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),

      ],
    );
  }
}
