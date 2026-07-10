import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import '../../theme/theme.dart';
import '../../app_shell.dart';

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

  int _failedAttempts = 0;
  int _lockoutSecondsRemaining = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _fetchKeys();
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
