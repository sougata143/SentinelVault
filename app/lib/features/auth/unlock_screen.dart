import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import '../../theme/theme.dart';
import '../../app_shell.dart';
import '../settings/settings_screen.dart';

class UnlockScreen extends StatefulWidget {
  final String email;
  final AuthClient? authClient;
  final String syncBaseUrl;
  final http.Client? httpClient;

  const UnlockScreen({
    super.key,
    required this.email,
    this.authClient,
    this.syncBaseUrl = 'http://localhost:3002',
    this.httpClient,
  });

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _masterPasswordController = TextEditingController();
  
  bool _isFetchingKeys = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _fetchErrorMessage;

  List<int>? _salt;
  List<int>? _wrappedVaultKey;
  List<int>? _recoverySalt;
  List<int>? _recoveryWrappedKey;

  int _failedAttempts = 0;
  int _lockoutSecondsRemaining = 0;
  Timer? _lockoutTimer;

  String? _biometricInvalidatedMessage;

  @override
  void initState() {
    super.initState();
    _fetchKeys();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    if (AppSettings.biometricEnabled && VaultLockManager.instance.hasBiometricCache) {
      final enrollmentChanged = await BiometricAuthService.instance.wasEnrollmentChanged();
      if (enrollmentChanged) {
        VaultLockManager.instance.invalidateBiometricCache();
        AppSettings.biometricEnabled = false;
        if (mounted) {
          setState(() {
            _biometricInvalidatedMessage = 'Biometric configuration changed. Please enter Master Password.';
          });
        }
        BiometricAuthService.instance.resetEnrollmentStatus();
      }
    }
  }

  @override
  void dispose() {
    _masterPasswordController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchKeys() async {
    setState(() {
      _isFetchingKeys = true;
      _fetchErrorMessage = null;
    });

    try {
      final syncClient = HttpSyncApiClient(
        baseUrl: widget.syncBaseUrl,
        userId: widget.email,
        httpClient: widget.httpClient,
      );

      final keysMap = await syncClient.fetchVaultKey();
      final saltHex = keysMap['salt']!;
      final wrappedKeyHex = keysMap['wrappedKey']!;

      setState(() {
        _salt = _hexToBytes(saltHex);
        _wrappedVaultKey = _hexToBytes(wrappedKeyHex);
        if (keysMap.containsKey('recoverySalt')) {
          _recoverySalt = _hexToBytes(keysMap['recoverySalt']!);
        } else {
          _recoverySalt = null;
        }
        if (keysMap.containsKey('recoveryWrappedKey')) {
          _recoveryWrappedKey = _hexToBytes(keysMap['recoveryWrappedKey']!);
        } else {
          _recoveryWrappedKey = null;
        }
        _isFetchingKeys = false;
      });
    } catch (e) {
      setState(() {
        _fetchErrorMessage = 'Failed to fetch vault credentials. Please check your connection.';
        _isFetchingKeys = false;
      });
    }
  }

  List<int> _hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    final len = hex.length ~/ 2;
    final bytes = Uint8List(len);
    for (var i = 0; i < len; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  void _startLockout(int seconds) {
    setState(() {
      _lockoutSecondsRemaining = seconds;
    });
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_lockoutSecondsRemaining > 1) {
          _lockoutSecondsRemaining--;
        } else {
          _lockoutSecondsRemaining = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleUnlock() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lockoutSecondsRemaining > 0) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final password = _masterPasswordController.text;

    bool navigated = false;
    try {
      final crypto = VaultCrypto();

      // 1. Derive the Master Key locally
      final masterKey = await crypto.deriveMasterKey(
        masterPassword: password,
        salt: _salt!,
      );

      // 2. Attempt to unwrap the Vault Key
      final vaultKey = await crypto.unwrapVaultKey(
        wrappedVaultKey: _wrappedVaultKey!,
        masterKey: masterKey,
      );

      // Reset failure counter on success
      setState(() {
        _failedAttempts = 0;
      });

      // Initialize database and open it
      final db = SqliteVaultDatabase.inMemory();
      db.open(vaultKey);

      navigated = true;
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AppShell(db: db, vaultKey: vaultKey),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      // 3. Increment failed attempts and trigger lockout delay
      setState(() {
        _failedAttempts++;
        _errorMessage = 'Incorrect master password';
      });

      int delay = 0;
      if (_failedAttempts >= 8) {
        delay = 15;
      } else if (_failedAttempts >= 5) {
        delay = 5;
      } else if (_failedAttempts >= 3) {
        delay = 2;
      }

      if (delay > 0) {
        _startLockout(delay);
      }
    } finally {
      if (!navigated && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleBiometricUnlock() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await BiometricAuthService.instance.authenticate();
      if (success) {
        final unlocked = VaultLockManager.instance.unlockWithBiometrics(true);
        if (unlocked) {
          final vaultKey = VaultLockManager.instance.vaultKey!;
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
          return;
        }
      }
      
      setState(() {
        _errorMessage = 'Biometric authentication failed';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Biometric unlock error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showRecoveryDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? dialogError;
    bool dialogLoading = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              title: const Text(
                'Recovery Key Unlock',
                style: TextStyle(color: AppTheme.textPrimaryColor, fontFamily: 'Outfit'),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter your 32-character offline Recovery Key to decrypt and unlock your vault.',
                      style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('recovery-key-input-field'),
                      controller: controller,
                      enabled: !dialogLoading,
                      style: const TextStyle(color: AppTheme.textPrimaryColor),
                      decoration: const InputDecoration(
                        labelText: 'Recovery Key',
                        hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Recovery Key is required';
                        }
                        final cleaned = value.replaceAll('-', '').replaceAll(' ', '');
                        if (cleaned.length != 32) {
                          return 'Must be exactly 32 alphanumeric characters';
                        }
                        return null;
                      },
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: const TextStyle(color: AppTheme.errorColor, fontSize: 13, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogLoading ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondaryColor)),
                ),
                ElevatedButton(
                  key: const Key('submit-recovery-key-button'),
                  onPressed: dialogLoading
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          
                          setDialogState(() {
                            dialogLoading = true;
                            dialogError = null;
                          });

                          try {
                            final crypto = VaultCrypto();
                            final enteredRK = controller.text;

                            // Derive Recovery KDF Key
                            final rkk = await crypto.deriveRecoveryKdfKey(
                              recoveryKey: enteredRK,
                              salt: _recoverySalt!,
                            );

                            // Decrypt the Vault Key
                            final vaultKey = await crypto.unwrapVaultKey(
                              wrappedVaultKey: _recoveryWrappedKey!,
                              masterKey: rkk,
                            );

                            // Success! Zero out memory, initialize DB
                            VaultLockManager.instance.unlockWithRecoveryKey(vaultKey);

                            final db = SqliteVaultDatabase.inMemory();
                            db.open(vaultKey);

                            if (mounted) {
                              Navigator.of(dialogCtx).pop(); // Close dialog
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => AppShell(db: db, vaultKey: vaultKey),
                                ),
                                (route) => false,
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              dialogLoading = false;
                              dialogError = 'Invalid Recovery Key or decryption failed';
                            });
                          }
                        },
                  child: dialogLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Unlock'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isButtonsDisabled = _isFetchingKeys || _isLoading || _lockoutSecondsRemaining > 0;

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
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield, color: AppTheme.primaryColor, size: 32),
                            SizedBox(width: 12),
                            Text(
                              'SentinelVault',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Vault is Locked',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_isFetchingKeys) ...[
                        const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Loading secure credentials...',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
                        ),
                      ] else if (_fetchErrorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            _fetchErrorMessage!,
                            style: const TextStyle(color: AppTheme.errorColor, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchKeys,
                          child: const Text('Retry'),
                        ),
                      ] else ...[
                        if (_biometricInvalidatedMessage != null) ...[
                          Container(
                            key: const Key('biometric-invalidated-banner'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Text(
                              _biometricInvalidatedMessage!,
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
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
                        if (_lockoutSecondsRemaining > 0) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Text(
                              'Too many failed attempts. Locked for $_lockoutSecondsRemaining seconds.',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          key: const Key('unlock-password-field'),
                          controller: _masterPasswordController,
                          obscureText: true,
                          enabled: _lockoutSecondsRemaining == 0 && !_isLoading,
                          decoration: const InputDecoration(
                            labelText: 'Master Password',
                            prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondaryColor),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Master password is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          key: const Key('decrypt-unlock-button'),
                          onPressed: isButtonsDisabled ? null : _handleUnlock,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Decrypt & Unlock Vault'),
                        ),
                        if (AppSettings.biometricEnabled && VaultLockManager.instance.hasBiometricCache) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('biometric-unlock-button'),
                            onPressed: isButtonsDisabled ? null : _handleBiometricUnlock,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Unlock with Biometrics'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryColor,
                              side: const BorderSide(color: AppTheme.primaryColor),
                            ),
                          ),
                        ],
                        if (_recoverySalt != null && _recoveryWrappedKey != null) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            key: const Key('use-recovery-key-button'),
                            onPressed: isButtonsDisabled ? null : _showRecoveryDialog,
                            child: const Text(
                              'Forgot Master Password? Use Recovery Key',
                              style: TextStyle(color: AppTheme.primaryColor),
                            ),
                          ),
                        ],
                      ],
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
