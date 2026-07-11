import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import '../../theme/theme.dart';
import '../auth/shamir_recovery_setup_screen.dart';
import 'duress_setup_screen.dart';

class AppSettings {
  static int clipboardTimeoutSeconds = 30;
  static bool autoLockEnabled = true;
  static int autoLockTimeoutMinutes = 5;
  static bool biometricEnabled = false;
}

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onLock;
  final VoidCallback? onLogout;
  final String currentEmail;
  final String syncBaseUrl;
  final http.Client? httpClient;

  const SettingsScreen({
    super.key,
    this.onLock,
    this.onLogout,
    this.currentEmail = 'auditor@sentinelvault.io',
    this.syncBaseUrl = 'http://localhost:3002',
    this.httpClient,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _clipboardTimeout;
  late bool _autoLock;
  late int _autoLockTimeout;
  late bool _biometricEnabled;

  bool _hasRecoveryKey = false;
  bool _isCheckingRecovery = true;

  @override
  void initState() {
    super.initState();
    _clipboardTimeout = AppSettings.clipboardTimeoutSeconds;
    _autoLock = AppSettings.autoLockEnabled;
    _autoLockTimeout = AppSettings.autoLockTimeoutMinutes;
    _biometricEnabled = AppSettings.biometricEnabled;
    _checkRecoveryStatus();
  }

  Future<void> _checkRecoveryStatus() async {
    if (!mounted) return;
    setState(() {
      _isCheckingRecovery = true;
    });
    try {
      final syncClient = HttpSyncApiClient(
        baseUrl: widget.syncBaseUrl,
        userId: widget.currentEmail,
        httpClient: widget.httpClient,
      );
      final keysMap = await syncClient.fetchVaultKey();
      if (mounted) {
        setState(() {
          _hasRecoveryKey = keysMap.containsKey('recoverySalt') && keysMap.containsKey('recoveryWrappedKey');
          _isCheckingRecovery = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingRecovery = false;
        });
      }
    }
  }

  Future<void> _handleSetupRecoveryKey() async {
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
                side: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              title: Text(
                _hasRecoveryKey ? 'Regenerate Emergency Kit' : 'Set up Emergency Kit',
                style: const TextStyle(color: AppTheme.textPrimaryColor, fontFamily: 'Outfit'),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Your Recovery Key is generated locally. Store it offline. If you lose it, we cannot recover it.',
                      style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                    // Checkbox confirming offline storage
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
                  onPressed: uploadLoading ? null : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondaryColor)),
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
                              userId: widget.currentEmail,
                              httpClient: widget.httpClient,
                            );

                            // 1. Fetch current keys from server to preserve masterPassword salt and wrapped key
                            final currentKeys = await syncClient.fetchVaultKey();
                            final saltHex = currentKeys['salt']!;
                            final wrappedKeyHex = currentKeys['wrappedKey']!;

                            // 2. Generate recovery salt and derive KDF key
                            final rkSalt = crypto.generateRandomBytes(16);
                            final rkk = await crypto.deriveRecoveryKdfKey(
                              recoveryKey: recoveryKey,
                              salt: rkSalt,
                            );

                            // 3. Wrap current vault key with recovery KDF key
                            final recoveryWrappedKey = await crypto.wrapVaultKey(
                              masterKey: rkk,
                              vaultKey: VaultLockManager.instance.vaultKey!,
                            );

                            final recoverySaltHex = rkSalt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
                            final recoveryWrappedKeyHex = recoveryWrappedKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

                            // 4. Upload updated bundle containing both paths
                            await syncClient.uploadVaultKey(
                              saltHex: saltHex,
                              wrappedKeyHex: wrappedKeyHex,
                              recoverySaltHex: recoverySaltHex,
                              recoveryWrappedKeyHex: recoveryWrappedKeyHex,
                            );

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Recovery Key successfully saved!')),
                              );
                              Navigator.of(dialogCtx).pop(); // Close dialog
                            }
                            _checkRecoveryStatus();
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

  void _saveSettings() {
    AppSettings.clipboardTimeoutSeconds = _clipboardTimeout;
    AppSettings.autoLockEnabled = _autoLock;
    AppSettings.autoLockTimeoutMinutes = _autoLockTimeout;
    AppSettings.biometricEnabled = _biometricEnabled;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved successfully')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile section
          _buildSectionHeader('Profile'),
          Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryColor,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text('Security Auditor'),
              subtitle: Text('auditor@sentinelvault.io'),
            ),
          ),
          const SizedBox(height: 20),

          // Security Settings
          _buildSectionHeader('Security Invariants'),
          Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  // Clipboard Timeout
                  ListTile(
                    title: const Text('Clipboard Auto-Clear Timeout'),
                    subtitle: Text('$_clipboardTimeout seconds'),
                    trailing: const Icon(Icons.timer_outlined, color: AppTheme.primaryColor),
                  ),
                  Slider(
                    value: _clipboardTimeout.toDouble(),
                    min: 10,
                    max: 120,
                    divisions: 11,
                    activeColor: AppTheme.primaryColor,
                    inactiveColor: Colors.grey[800],
                    onChanged: (val) {
                      setState(() {
                        _clipboardTimeout = val.toInt();
                      });
                      _saveSettings();
                    },
                  ),
                  const Divider(color: Colors.white10),

                  // Auto-Lock toggle
                  SwitchListTile(
                    title: const Text('Auto-Lock Vault'),
                    subtitle: const Text('Locks the vault automatically after inactivity'),
                    value: _autoLock,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) {
                      setState(() {
                        _autoLock = val;
                      });
                      _saveSettings();
                    },
                  ),

                  if (_autoLock) ...[
                    const Divider(color: Colors.white10),
                    ListTile(
                      title: const Text('Auto-Lock Timeout'),
                      subtitle: Text('$_autoLockTimeout minutes'),
                      trailing: const Icon(Icons.hourglass_empty, color: AppTheme.primaryColor),
                    ),
                    Slider(
                      value: _autoLockTimeout.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      activeColor: AppTheme.primaryColor,
                      inactiveColor: Colors.grey[800],
                      onChanged: (val) {
                        setState(() {
                          _autoLockTimeout = val.toInt();
                        });
                        _saveSettings();
                      },
                    ),
                  ],
                  const Divider(color: Colors.white10),
                  SwitchListTile(
                    key: const Key('settings-biometric-switch'),
                    title: const Text('Biometric Quick-Unlock'),
                    subtitle: const Text('Unlock the vault using Face ID or fingerprint after in-app locks'),
                    value: _biometricEnabled,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) async {
                      if (val) {
                        final supported = await BiometricAuthService.instance.isBiometricsSupported();
                        if (!supported) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Biometrics not supported on this device')),
                            );
                          }
                          return;
                        }

                        final success = await BiometricAuthService.instance.authenticate();
                        if (success) {
                          setState(() {
                            _biometricEnabled = true;
                          });
                          _saveSettings();
                          if (VaultLockManager.instance.masterKey != null &&
                              VaultLockManager.instance.vaultKey != null) {
                            await VaultLockManager.instance.enableBiometrics(
                              VaultLockManager.instance.masterKey!,
                              VaultLockManager.instance.vaultKey!,
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Biometric authentication failed')),
                            );
                          }
                        }
                      } else {
                        setState(() {
                          _biometricEnabled = false;
                        });
                        _saveSettings();
                        VaultLockManager.instance.disableBiometrics();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // About Section
          _buildSectionHeader('System Information'),
          Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Column(
              children: [
                ListTile(
                  title: Text('Version'),
                  trailing: Text('1.2.0 (Production)'),
                ),
                Divider(color: Colors.white10, height: 1),
                ListTile(
                  title: Text('Crypto Provider'),
                  trailing: Text('libsodium binding'),
                ),
                Divider(color: Colors.white10, height: 1),
                ListTile(
                  title: Text('Data Location'),
                  trailing: Text('Encrypted SQLite (Zero-Knowledge)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Emergency Kit Section
          _buildSectionHeader('Emergency Kit'),
          Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  key: const Key('settings-setup-emergency-kit-tile'),
                  leading: const Icon(Icons.key, color: AppTheme.primaryColor),
                  title: const Text('Emergency Kit Recovery Key'),
                  subtitle: Text(_isCheckingRecovery
                      ? 'Checking recovery status...'
                      : _hasRecoveryKey
                          ? 'Recovery Key is active. Click to regenerate.'
                          : 'Set up an offline Recovery Key to prevent permanent lockouts.'),
                  trailing: _isCheckingRecovery
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                        )
                      : Icon(_hasRecoveryKey ? Icons.sync : Icons.add, color: AppTheme.primaryColor),
                  onTap: _isCheckingRecovery ? null : _handleSetupRecoveryKey,
                ),
                const Divider(color: Colors.white10, height: 1),
                ListTile(
                  key: const Key('settings-setup-shamir-recovery-tile'),
                  leading: const Icon(Icons.people, color: AppTheme.primaryColor),
                  title: const Text('Split Recovery Key (Shamir M-of-N)'),
                  subtitle: Text(_isCheckingRecovery
                      ? 'Checking recovery status...'
                      : _hasRecoveryKey
                          ? 'Shamir split recovery is configured. Click to configure again.'
                          : 'Distribute your Recovery Key among trusted contacts (M-of-N).'),
                  trailing: Icon(_hasRecoveryKey ? Icons.sync : Icons.add, color: AppTheme.primaryColor),
                  onTap: _isCheckingRecovery ? null : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ShamirRecoverySetupScreen(
                          currentEmail: widget.currentEmail,
                          syncBaseUrl: widget.syncBaseUrl,
                          httpClient: widget.httpClient ?? http.Client(),
                        ),
                      ),
                    );
                    _checkRecoveryStatus();
                  },
                ),
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  key: const Key('settings-duress-decoy-tile'),
                  leading: const Icon(Icons.shield_outlined, color: Colors.deepOrangeAccent),
                  title: const Text('Decoy Vault (Duress Mode)'),
                  subtitle: const Text(
                    'Set a separate unlock password that opens a harmless decoy vault '
                    'under coercion, clearing your real vault\'s quick-unlock cache.',
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DuressSetupScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Session Actions
          _buildSectionHeader('Session Actions'),
          Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  key: const Key('settings-lock-tile'),
                  leading: const Icon(Icons.lock_outline, color: Colors.orange),
                  title: const Text('Lock Vault Now'),
                  subtitle: const Text('Clears key material from memory. Session remains active.'),
                  onTap: () {
                    if (widget.onLock != null) {
                      widget.onLock!();
                    } else {
                      VaultLockManager.instance.lock();
                      Navigator.of(context).pop();
                    }
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                ListTile(
                  key: const Key('settings-logout-tile'),
                  leading: const Icon(Icons.exit_to_app, color: AppTheme.errorColor),
                  title: const Text('Log Out'),
                  subtitle: const Text('Clears session token and locks vault. Full login required next access.'),
                  onTap: () {
                    if (widget.onLogout != null) {
                      widget.onLogout!();
                    } else {
                      VaultLockManager.instance.logout();
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
