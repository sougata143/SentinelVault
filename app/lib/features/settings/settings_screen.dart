import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class AppSettings {
  static int clipboardTimeoutSeconds = 30;
  static bool autoLockEnabled = true;
  static int autoLockTimeoutMinutes = 5;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _clipboardTimeout;
  late bool _autoLock;
  late int _autoLockTimeout;

  @override
  void initState() {
    super.initState();
    _clipboardTimeout = AppSettings.clipboardTimeoutSeconds;
    _autoLock = AppSettings.autoLockEnabled;
    _autoLockTimeout = AppSettings.autoLockTimeoutMinutes;
  }

  void _saveSettings() {
    AppSettings.clipboardTimeoutSeconds = _clipboardTimeout;
    AppSettings.autoLockEnabled = _autoLock;
    AppSettings.autoLockTimeoutMinutes = _autoLockTimeout;
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
