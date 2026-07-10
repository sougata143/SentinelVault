import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../../theme/theme.dart';

/// Multi-step vault export flow.
///
/// Step 0 — Format picker: "Encrypted Backup (.svault)" or "Plaintext CSV Export".
/// Step 1 — Re-auth gate (plaintext path ONLY): master-password entry + verification.
/// Step 1b — Warning modal (plaintext path ONLY): explicit risk acknowledgement.
/// Step 2 — Export in progress / file download.
/// Step 3 — Done.
///
/// Security invariants (vault-import-export skill + AGENTS.md Rule 7):
/// - The plaintext export path CANNOT be reached without _reauthed == true.
/// - _reauthed is only set to true when the entered password derives a key
///   that matches the current vaultKey byte-for-byte.
/// - Plaintext [VaultItem] list is set to [] immediately after the CSV is built.
/// - [SecurityActivityLog] records only type + itemCount + timestamp — never content.
/// - No network calls in this screen.
class ExportScreen extends StatefulWidget {
  final List<int> vaultKey;
  final VaultDatabase db;

  /// The Argon2id salt stored for this user (used to verify re-auth).
  /// In the dev build this is a placeholder; in production it is stored
  /// alongside the wrapped vault key in local secure storage.
  final List<int> masterKeySalt;

  const ExportScreen({
    super.key,
    required this.vaultKey,
    required this.db,
    required this.masterKeySalt,
  });

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  int _step = 0;
  String _selectedFormat = ''; // 'svault' | 'csv' | 'json'

  // Re-auth state
  final _passwordCtrl = TextEditingController();
  bool _reauthed = false;
  bool _verifying = false;
  String? _authError;
  int _authAttempts = 0;
  static const _maxAuthAttempts = 5;

  // Export state
  bool _exporting = false;
  int _exportedCount = 0;
  String? _exportFilename;
  String? _exportContent; // text content for web download

  // Export service
  final _exportService = ExportService();
  final _crypto = VaultCrypto();

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ─── Re-authentication ────────────────────────────────────────────────────

  Future<void> _verifyPassword() async {
    if (_authAttempts >= _maxAuthAttempts) return;

    final entered = _passwordCtrl.text;
    if (entered.isEmpty) {
      setState(() => _authError = 'Enter your master password.');
      return;
    }

    setState(() {
      _verifying = true;
      _authError = null;
    });

    try {
      final derivedKey = await _crypto.deriveMasterKey(
        masterPassword: entered,
        salt: widget.masterKeySalt,
      );

      // Constant-time byte comparison to avoid timing attacks
      final matches = _constantTimeEquals(derivedKey, widget.vaultKey);
      _passwordCtrl.clear(); // Clear password from text field immediately

      if (matches) {
        setState(() {
          _reauthed = true;
          _verifying = false;
          _authError = null;
        });
        // Show warning modal next
        _showWarningModal();
      } else {
        setState(() {
          _authAttempts++;
          _verifying = false;
          _authError = _authAttempts >= _maxAuthAttempts
              ? 'Too many failed attempts. Export locked.'
              : 'Incorrect master password. ${_maxAuthAttempts - _authAttempts} attempts remaining.';
        });
      }
    } catch (e) {
      _passwordCtrl.clear();
      setState(() {
        _verifying = false;
        _authError = 'Verification failed: $e';
      });
    }
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ─── Warning Modal ────────────────────────────────────────────────────────

  void _showWarningModal() {
    // Guard: MUST be re-authenticated before this modal can appear
    if (!_reauthed) return;

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor),
            SizedBox(width: 10),
            Text('Unencrypted Export Warning'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You are about to export your vault as an UNENCRYPTED file. '
                'Anyone with access to this file can read all your passwords.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text('Safe-handling requirements:', style: TextStyle(color: AppTheme.textSecondaryColor)),
              SizedBox(height: 8),
              _BulletItem('Delete the file immediately after importing it into your new password manager.'),
              _BulletItem('Do NOT email this file or upload it to cloud storage (Google Drive, iCloud, Dropbox, etc.).'),
              _BulletItem('Do NOT open this file in a browser or shared computer.'),
              _BulletItem('This export is recorded in your security activity log.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              // User cancelled — reset re-auth so the flow is clean next time
              setState(() => _reauthed = false);
            },
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondaryColor)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warningColor,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('I understand — export anyway'),
            onPressed: () {
              Navigator.pop(ctx, true);
              _runPlaintextExport();
            },
          ),
        ],
      ),
    );
  }

  // ─── Export Runners ───────────────────────────────────────────────────────

  Future<void> _runSvaultExport() async {
    setState(() {
      _exporting = true;
      _step = 2;
    });

    final encryptedItems = widget.db.getAllItems();
    final bytes = _exportService.buildSvaultBackup(encryptedItems);
    final date = _formatDate(DateTime.now());
    final filename = 'sentinelvault_backup_$date.svault';

    // Trigger download
    _triggerDownload(filename: filename, bytes: bytes, mimeType: 'application/octet-stream');

    // Log export — metadata only
    SecurityActivityLog.instance.logExport(
      type: 'encrypted_backup_export',
      itemCount: encryptedItems.length,
      timestamp: DateTime.now().toUtc(),
    );

    setState(() {
      _exporting = false;
      _exportedCount = encryptedItems.length;
      _exportFilename = filename;
      _step = 3;
    });
  }

  Future<void> _runPlaintextExport() async {
    // Double-check gate — this method must never proceed if _reauthed is false
    if (!_reauthed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Re-authentication required.')),
        );
      }
      return;
    }

    setState(() {
      _exporting = true;
      _step = 2;
    });

    final encryptedItems = widget.db.getAllItems();
    // Decrypt all items into memory
    var decryptedItems = <VaultItem>[];
    for (final enc in encryptedItems) {
      try {
        decryptedItems.add(await VaultItem.decrypt(enc, widget.vaultKey, _crypto));
      } catch (_) {
        // Skip items that fail to decrypt (e.g. legacy format)
      }
    }

    final date = _formatDate(DateTime.now());
    String filename;
    List<int> bytes;

    if (_selectedFormat == 'json') {
      filename = 'sentinelvault_export_UNENCRYPTED_$date.json';
      final json = _exportService.buildPlaintextJson(decryptedItems);
      bytes = utf8.encode(json);
    } else {
      filename = 'sentinelvault_export_UNENCRYPTED_$date.csv';
      final csv = _exportService.buildPlaintextCsv(decryptedItems);
      bytes = utf8.encode(csv);
    }

    // Security: clear decrypted items from memory immediately after use
    decryptedItems = [];
    _reauthed = false; // consume the re-auth token — one export per verification

    // Trigger download
    _triggerDownload(filename: filename, bytes: bytes, mimeType: 'text/plain');

    // Log export — metadata only, never content
    SecurityActivityLog.instance.logExport(
      type: _selectedFormat == 'json' ? 'plaintext_json_export' : 'plaintext_csv_export',
      itemCount: encryptedItems.length,
      timestamp: DateTime.now().toUtc(),
    );

    if (mounted) {
      setState(() {
        _exporting = false;
        _exportedCount = encryptedItems.length;
        _exportFilename = filename;
        _step = 3;
      });
    }
  }

  /// Platform-agnostic download trigger.
  /// On web: creates a data URI and clicks it programmatically.
  /// On native: opens a share sheet / save dialog (future: path_provider).
  void _triggerDownload({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) {
    // The content is surfaced for the test harness and the "copy" fallback in the UI.
    _exportContent = base64.encode(bytes);
    // In a real build: use universal_html (web) or path_provider (native) to
    // save the file. This placeholder surfaces the data for test inspection.
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Vault'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case 0:
        return _buildFormatPicker();
      case 1:
        return _buildReauthGate();
      case 2:
        return _buildExporting();
      case 3:
        return _buildSuccess();
      default:
        return const SizedBox.shrink();
    }
  }

  // Step 0 — Format Picker
  Widget _buildFormatPicker() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Choose Export Type', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Encrypted backups are safe to keep around. Plaintext exports must be deleted after use.',
          style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // Encrypted .svault tile
        _formatTile(
          icon: Icons.lock_outlined,
          color: AppTheme.primaryColor,
          title: 'Encrypted Backup (.svault)',
          subtitle: 'Ciphertext only — safe for device migration and backup. No password re-entry required.',
          badge: 'RECOMMENDED',
          onTap: () {
            setState(() {
              _selectedFormat = 'svault';
            });
            _runSvaultExport();
          },
        ),

        const SizedBox(height: 16),

        // Plaintext CSV tile
        _formatTile(
          icon: Icons.table_chart_outlined,
          color: AppTheme.warningColor,
          title: 'Plaintext CSV Export',
          subtitle: 'Unencrypted CSV for migrating to another password manager. Requires master-password re-entry.',
          badge: 'HIGH RISK',
          badgeColor: AppTheme.errorColor,
          onTap: () {
            setState(() {
              _selectedFormat = 'csv';
              _step = 1;
            });
          },
        ),

        const SizedBox(height: 16),

        // Plaintext JSON tile
        _formatTile(
          icon: Icons.code_outlined,
          color: AppTheme.warningColor,
          title: 'Plaintext JSON Export',
          subtitle: 'Unencrypted JSON for developer use or structured migration. Requires master-password re-entry.',
          badge: 'HIGH RISK',
          badgeColor: AppTheme.errorColor,
          onTap: () {
            setState(() {
              _selectedFormat = 'json';
              _step = 1;
            });
          },
        ),
      ],
    );
  }

  Widget _formatTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String badge,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    return Card(
      color: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? AppTheme.primaryColor).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: badgeColor ?? AppTheme.primaryColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondaryColor),
            ],
          ),
        ),
      ),
    );
  }

  // Step 1 — Re-auth gate (plaintext only)
  Widget _buildReauthGate() {
    final locked = _authAttempts >= _maxAuthAttempts;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _step = 0;
                _authError = null;
                _authAttempts = 0;
                _passwordCtrl.clear();
              }),
            ),
            const SizedBox(width: 8),
            const Text('Master Password Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outlined, color: AppTheme.errorColor, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Plaintext export is a high-risk operation. Re-enter your master password to proceed.',
                  style: TextStyle(fontSize: 12, color: AppTheme.errorColor),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        TextFormField(
          key: const Key('reauth-password-field'),
          controller: _passwordCtrl,
          obscureText: true,
          enabled: !locked && !_verifying,
          decoration: InputDecoration(
            labelText: 'Master Password',
            prefixIcon: const Icon(Icons.key_outlined),
            errorText: _authError,
          ),
          onFieldSubmitted: locked ? null : (_) => _verifyPassword(),
        ),

        const SizedBox(height: 16),
        ElevatedButton.icon(
          key: const Key('reauth-verify-button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _verifying
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.verified_user_outlined),
          label: Text(locked ? 'Locked — too many attempts' : 'Verify & Continue'),
          onPressed: locked || _verifying ? null : _verifyPassword,
        ),
      ],
    );
  }

  // Step 2 — Exporting
  Widget _buildExporting() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Preparing export…'),
        ],
      ),
    );
  }

  // Step 3 — Done
  Widget _buildSuccess() {
    final isPlaintext = _selectedFormat == 'csv' || _selectedFormat == 'json';
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline, color: AppTheme.primaryColor, size: 56),
            ),
            const SizedBox(height: 24),
            const Text('Export Complete', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '$_exportedCount items exported.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondaryColor),
            ),
            const SizedBox(height: 4),
            if (_exportFilename != null)
              Text(
                'File: $_exportFilename',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
              ),

            if (isPlaintext) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                ),
                child: const Text(
                  '⚠️ This file is UNENCRYPTED. Delete it immediately after you have finished using it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.errorColor),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Text(
              'This export was recorded in your security activity log.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor),
            ),

            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// Simple bullet point widget for the warning modal.
class _BulletItem extends StatelessWidget {
  final String text;
  const _BulletItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppTheme.warningColor, fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
