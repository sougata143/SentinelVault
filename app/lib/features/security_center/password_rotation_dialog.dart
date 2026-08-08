import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/theme.dart';

class PasswordRotationDialog extends StatefulWidget {
  final VaultItem item;
  final List<int> vaultKey;
  final VaultDatabase db;
  final Function(VaultItem updatedItem)? onRotated;
  final Function(String url)? urlLauncherOverride;

  const PasswordRotationDialog({
    super.key,
    required this.item,
    required this.vaultKey,
    required this.db,
    this.onRotated,
    this.urlLauncherOverride,
  });

  @override
  State<PasswordRotationDialog> createState() => _PasswordRotationDialogState();
}

class _PasswordRotationDialogState extends State<PasswordRotationDialog> {
  late String _generatedPassword;
  int _length = 20;
  final bool _includeUppercase = true;
  final bool _includeLowercase = true;
  final bool _includeNumbers = true;
  final bool _includeSymbols = true;

  bool _siteChangedConfirmed = false;
  bool _isSaving = false;
  bool _isRotated = false;
  VaultItem? _updatedItem;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _regeneratePassword();
  }

  void _regeneratePassword() {
    setState(() {
      _generatedPassword = PasswordGenerator.generate(
        length: _length,
        includeUppercase: _includeUppercase,
        includeLowercase: _includeLowercase,
        includeNumbers: _includeNumbers,
        includeSymbols: _includeSymbols,
      );
    });
  }

  Future<void> _launchUrl(String urlStr) async {
    if (widget.urlLauncherOverride != null) {
      widget.urlLauncherOverride!(urlStr);
      return;
    }

    try {
      var uriStr = urlStr.trim();
      if (!uriStr.startsWith('http://') && !uriStr.startsWith('https://')) {
        uriStr = 'https://$uriStr';
      }
      final uri = Uri.parse(uriStr);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch URL: $urlStr')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open link: $e')),
        );
      }
    }
  }

  Future<void> _handleConfirmRotation() async {
    if (!_siteChangedConfirmed) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final crypto = VaultCrypto();
      VaultItemFields updatedFields = widget.item.fields;

      if (widget.item.fields is LoginFields) {
        final lf = widget.item.fields as LoginFields;
        updatedFields = lf.rotatePassword(newPassword: _generatedPassword);
      } else if (widget.item.fields is PasswordFields) {
        updatedFields = PasswordFields(password: ConcealedValue.plain(_generatedPassword));
      }

      final now = DateTime.now();
      final newItem = VaultItem(
        id: widget.item.id,
        type: widget.item.type,
        title: widget.item.title,
        tags: widget.item.tags,
        favorite: widget.item.favorite,
        vaultId: widget.item.vaultId,
        createdAt: widget.item.createdAt,
        updatedAt: now,
        fields: updatedFields,
        customFields: widget.item.customFields,
        notes: widget.item.notes,
      );

      final encrypted = await newItem.encrypt(widget.vaultKey, crypto);
      try {
        widget.db.updateItem(encrypted);
      } catch (_) {
        widget.db.insertItem(encrypted);
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isRotated = true;
          _updatedItem = newItem;
        });
      }

      if (widget.onRotated != null) {
        widget.onRotated!(newItem);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to rotate password: $e';
        });
      }
    }
  }

  Future<void> _handleRollback() async {
    if (_updatedItem == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final crypto = VaultCrypto();
      VaultItemFields rolledBackFields = _updatedItem!.fields;

      if (_updatedItem!.fields is LoginFields) {
        final lf = _updatedItem!.fields as LoginFields;
        rolledBackFields = lf.rollbackPassword();
      }

      final now = DateTime.now();
      final rolledBackItem = VaultItem(
        id: _updatedItem!.id,
        type: _updatedItem!.type,
        title: _updatedItem!.title,
        tags: _updatedItem!.tags,
        favorite: _updatedItem!.favorite,
        vaultId: _updatedItem!.vaultId,
        createdAt: _updatedItem!.createdAt,
        updatedAt: now,
        fields: rolledBackFields,
        customFields: _updatedItem!.customFields,
        notes: _updatedItem!.notes,
      );

      final encrypted = await rolledBackItem.encrypt(widget.vaultKey, crypto);
      try {
        widget.db.updateItem(encrypted);
      } catch (_) {
        widget.db.insertItem(encrypted);
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isRotated = false;
          _updatedItem = rolledBackItem;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password rolled back to previous version.')),
        );
        Navigator.of(context).pop();
      }

      if (widget.onRotated != null) {
        widget.onRotated!(rolledBackItem);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to rollback password: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<String> storedUrls = [];
    if (widget.item.fields is LoginFields) {
      storedUrls = (widget.item.fields as LoginFields).urls;
    }

    final strength = PasswordAnalyzer.analyze(_generatedPassword);
    final scoreColor = strength.score >= 3 ? AppTheme.primaryColor : AppTheme.warningColor;

    return Dialog(
      backgroundColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync, color: AppTheme.primaryColor, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Rotate Password: ${widget.item.title}',
                        style: const TextStyle(
                          color: AppTheme.textPrimaryColor,
                          fontFamily: 'Outfit',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textSecondaryColor),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_isRotated) ...[
                  // Success & Rollback Screen
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 24),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Password Rotated Successfully!',
                                style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your vault item has been updated and your previous password was safely archived to item history.',
                          style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'If the change on the target website failed or didn\'t go through, you can undo this rotation.',
                          style: TextStyle(color: AppTheme.textPrimaryColor, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          key: const Key('rollback-rotation-btn'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _isSaving ? null : _handleRollback,
                          icon: const Icon(Icons.undo),
                          label: const Text('Undo / Rollback Previous Password'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ] else ...[
                  // Step 1: Website Link Launcher
                  const Text(
                    'STEP 1: OPEN WEBSITE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  if (storedUrls.isNotEmpty)
                    ElevatedButton.icon(
                      key: const Key('launch-website-btn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surfaceColor,
                        foregroundColor: AppTheme.primaryColor,
                        side: const BorderSide(color: AppTheme.primaryColor),
                      ),
                      onPressed: () => _launchUrl(storedUrls.first),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text('Open ${storedUrls.first}'),
                    )
                  else
                    const Text(
                      'No URL stored for this item. Open the target website to change your password.',
                      style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 12),
                    ),
                  const SizedBox(height: 20),

                  // Step 2: Generator
                  const Text(
                    'STEP 2: GENERATE NEW STRONG PASSWORD',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _generatedPassword,
                            key: const Key('generated-password-display'),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
                          onPressed: _regeneratePassword,
                          tooltip: 'Regenerate Password',
                        ),
                        IconButton(
                          key: const Key('copy-generated-password-btn'),
                          icon: const Icon(Icons.copy, color: AppTheme.primaryColor),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _generatedPassword));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('New password copied to clipboard!')),
                            );
                          },
                          tooltip: 'Copy to Clipboard',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Strength: ', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 12)),
                      Text(
                        'Score ${strength.score}/4 (${strength.estimatedCrackTime})',
                        style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Length slider
                  Row(
                    children: [
                      Text('Length: $_length', style: const TextStyle(color: AppTheme.textPrimaryColor, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _length.toDouble(),
                          min: 8,
                          max: 64,
                          divisions: 56,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            setState(() {
                              _length = val.toInt();
                            });
                            _regeneratePassword();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Step 3: Confirmation Check
                  const Text(
                    'STEP 3: CONFIRM SITE UPDATE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor, letterSpacing: 1),
                  ),
                  CheckboxListTile(
                    key: const Key('confirm-site-change-checkbox'),
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.primaryColor,
                    title: const Text(
                      'I have updated my password on the website using this new password.',
                      style: TextStyle(color: AppTheme.textPrimaryColor, fontSize: 12),
                    ),
                    value: _siteChangedConfirmed,
                    onChanged: (val) {
                      setState(() {
                        _siteChangedConfirmed = val ?? false;
                      });
                    },
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_errorMessage!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 12)),
                  ],

                  const SizedBox(height: 16),
                  ElevatedButton(
                    key: const Key('confirm-rotate-save-btn'),
                    onPressed: (!_siteChangedConfirmed || _isSaving) ? null : _handleConfirmRotation,
                    child: _isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save & Rotate Vault Item'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
