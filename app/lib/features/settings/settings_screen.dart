import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';

class AppSettings {
  static int clipboardTimeoutSeconds = 30;
  static bool autoLockEnabled = true;
  static int autoLockTimeoutMinutes = 5;
  static bool biometricEnabled = false;
}

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onLock;
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    this.onLock,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _clipboardTimeout;
  late bool _autoLock;
  late int _autoLockTimeout;
  late bool _biometricEnabled;

  @override
  void initState() {
    super.initState();
    _clipboardTimeout = AppSettings.clipboardTimeoutSeconds;
    _autoLock = AppSettings.autoLockEnabled;
    _autoLockTimeout = AppSettings.autoLockTimeoutMinutes;
    _biometricEnabled = AppSettings.biometricEnabled;
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
                            VaultLockManager.instance.enableBiometrics(
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
