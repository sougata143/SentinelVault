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

      // 6. Open in-memory DB
      final db = SqliteVaultDatabase.inMemory();
      db.open(vaultKey);

      // Set VaultLockManager session and unlock state
      VaultLockManager.instance.unlock(masterKey, vaultKey);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
            title: const Text(
              'Set Up Emergency Kit?',
              style: TextStyle(color: AppTheme.textPrimaryColor, fontFamily: 'Outfit'),
            ),
            content: const Text(
              'We highly recommend generating an Emergency Kit Recovery Key. '
              'If you forget your Master Password, this key will let you unlock your vault. '
              'Without it, your data could be lost forever.',
              style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
            ),
            actions: [
              TextButton(
                key: const Key('setup-recovery-skip-button'),
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  _navigateToDashboard(db, vaultKey);
                },
                child: const Text('Do it later', style: TextStyle(color: AppTheme.textSecondaryColor)),
              ),
              ElevatedButton(
                key: const Key('setup-recovery-now-button'),
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  _setupRecoveryFlowAndNavigate(vaultKey, saltHex, wrappedKeyHex, db);
                },
                child: const Text('Set up Now'),
              ),
            ],
          ),
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
                side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
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
                            color: AppTheme.errorColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
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

  Future<void> _setupRecoveryFlowAndNavigate(
    List<int> vaultKey,
    String saltHex,
    String wrappedKeyHex,
    SqliteVaultDatabase db,
  ) async {
    final crypto = VaultCrypto();
    final recoveryKey = crypto.generateRecoveryKey();
    final printConfirmed = ValueNotifier<bool>(false);
    bool uploadLoading = false;
    String? uploadError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              title: const Text(
                'Your Recovery Key',
                style: TextStyle(color: AppTheme.textPrimaryColor, fontFamily: 'Outfit'),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Store this key safely offline. It will never be shown again and cannot be recovered by our team.',
                      style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Text(
                        recoveryKey,
                        key: const Key('generated-recovery-key-text'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedBuilder(
                      animation: printConfirmed,
                      builder: (context, _) {
                        return CheckboxListTile(
                          key: const Key('confirm-saved-checkbox'),
                          title: const Text(
                            'I have written down or safely saved this Recovery Key.',
                            style: TextStyle(color: AppTheme.textPrimaryColor, fontSize: 12),
                          ),
                          value: printConfirmed.value,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            setDialogState(() {
                              printConfirmed.value = val ?? false;
                            });
                          },
                        );
                      },
                    ),
                    if (uploadError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        uploadError!,
                        style: const TextStyle(color: AppTheme.errorColor, fontSize: 13, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: uploadLoading
                      ? null
                      : () {
                          Navigator.of(dialogCtx).pop();
                          _navigateToDashboard(db, vaultKey);
                        },
                  child: const Text('Skip / Cancel', style: TextStyle(color: AppTheme.textSecondaryColor)),
                ),
                ElevatedButton(
                  key: const Key('upload-recovery-key-button'),
                  onPressed: (uploadLoading || !printConfirmed.value)
                      ? null
                      : () async {
                          setDialogState(() {
                            uploadLoading = true;
                            uploadError = null;
                          });

                          try {
                            final syncClient = HttpSyncApiClient(
                              baseUrl: widget.syncBaseUrl,
                              userId: widget.email,
                              httpClient: widget.httpClient,
                            );

                            final rkSalt = crypto.generateRandomBytes(16);
                            final rkk = await crypto.deriveRecoveryKdfKey(
                              recoveryKey: recoveryKey,
                              salt: rkSalt,
                            );

                            final recoveryWrappedKey = await crypto.wrapVaultKey(
                              masterKey: rkk,
                              vaultKey: vaultKey,
                            );

                            final recoverySaltHex = rkSalt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
                            final recoveryWrappedKeyHex = recoveryWrappedKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

                            await syncClient.uploadVaultKey(
                              saltHex: saltHex,
                              wrappedKeyHex: wrappedKeyHex,
                              recoverySaltHex: recoverySaltHex,
                              recoveryWrappedKeyHex: recoveryWrappedKeyHex,
                            );

                            if (dialogCtx.mounted) {
                              Navigator.of(dialogCtx).pop();
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Recovery Key successfully saved!')),
                              );
                              _navigateToDashboard(db, vaultKey);
                            }
                          } catch (e) {
                            setDialogState(() {
                              uploadLoading = false;
                              uploadError = 'Failed to upload Recovery Key. Please try again.';
                            });
                          }
                        },
                  child: uploadLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Finish Setup'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToDashboard(SqliteVaultDatabase db, List<int> vaultKey) {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AppShell(db: db, vaultKey: vaultKey),
        ),
        (route) => false,
      );
    }
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
            final barColor = isFilled ? color : Colors.white.withValues(alpha: 0.1);
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
