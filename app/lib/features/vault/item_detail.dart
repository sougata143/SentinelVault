import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';
import '../settings/settings_screen.dart';
import 'sharing/sharing_screen.dart';
import 'sharing/share_item_dialog.dart';
import 'totp_code_card.dart';

class ItemDetailPane extends StatefulWidget {
  final VaultItem? item;
  final List<int>? vaultKey;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const ItemDetailPane({
    super.key,
    required this.item,
    this.vaultKey,
    this.onDelete,
    this.onEdit,
  });

  @override
  State<ItemDetailPane> createState() => _ItemDetailPaneState();
}

class _ItemDetailPaneState extends State<ItemDetailPane> {
  final Map<String, bool> _obscuredFields = {};
  Timer? _clipboardTimer;
  int _secondsRemaining = 0;

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    super.dispose();
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    _clipboardTimer?.cancel();

    final timeout = AppSettings.clipboardTimeoutSeconds;
    setState(() {
      _secondsRemaining = timeout;
    });

    _clipboardTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 1) {
          _secondsRemaining--;
        } else {
          Clipboard.setData(const ClipboardData(text: ''));
          _secondsRemaining = 0;
          timer.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clipboard auto-cleared for security')),
          );
        }
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label — clearing in $_secondsRemaining seconds'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isObscured(String key) {
    return _obscuredFields[key] ?? true;
  }

  void _toggleObscure(String key) {
    setState(() {
      _obscuredFields[key] = !_isObscured(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    if (item == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: AppTheme.textSecondaryColor),
            SizedBox(height: 16),
            Text(
              'Select an item to view details',
              style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(item.title, style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.link, color: SentinelTheme.accentCyan),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => ShareItemDialog(
                  item: item,
                  sharingBaseUrl: '',
                  sessionToken: VaultLockManager.instance.sessionToken,
                ),
              );
            },
            tooltip: 'Share via One-Time Link',
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.teal),
            onPressed: () {
              final targetId = item.vaultId.isNotEmpty ? item.vaultId : item.id;
              final folderKey = (widget.vaultKey != null && widget.vaultKey!.isNotEmpty)
                  ? deriveFolderKey(widget.vaultKey!, targetId)
                  : Uint8List.fromList(List.generate(32, (i) => i));

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SharingScreen(
                    folderId: targetId,
                    folderName: item.vaultId.isNotEmpty ? item.vaultId : item.title,
                    currentFolderKey: folderKey,
                    senderUserId: VaultLockManager.instance.sessionToken ?? 'current-user',
                    itemToShare: item,
                    db: widget.db,
                  ),
                ),
              );
            },
            tooltip: 'Share Item',
          ),
          if (widget.onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
              onPressed: widget.onEdit,
              tooltip: 'Edit Item',
            ),
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
              onPressed: widget.onDelete,
              tooltip: 'Delete Item',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Clipboard active notification
          if (_secondsRemaining > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Clipboard contains sensitive info! Auto-clears in $_secondsRemaining seconds.',
                      style: const TextStyle(color: AppTheme.warningColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Shared Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildTypeIcon(item.type),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.type.toValue().toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (item.favorite)
                  const Icon(Icons.star, color: AppTheme.warningColor, size: 24),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Type specific fields card container
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildTypeFields(item),
            ),
          ),

          // Custom Fields Section
          if (item.customFields.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CUSTOM FIELDS',
                    style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 16),
                  ...item.customFields.map((cf) => _buildDetailField(
                        cf.label,
                        cf.value.plaintext ?? '',
                        isSecret: cf.type == 'concealed',
                        obscureKey: 'cf_${cf.label}',
                      )),
                ],
              ),
            ),
          ],

          // Notes Section
          if (item.notes.plaintext != null && item.notes.plaintext!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NOTES',
                    style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.notes.plaintext!,
                    style: const TextStyle(height: 1.5, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
          // Password History & Rollback Section
          if (item.fields is LoginFields && (item.fields as LoginFields).passwordHistory.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PASSWORD HISTORY & ROLLBACK',
                        style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                      Text(
                        '${(item.fields as LoginFields).passwordHistory.length} previous version(s)',
                        style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...(item.fields as LoginFields).passwordHistory.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final hist = entry.value;
                    final histPwd = hist.password.plaintext ?? '••••••••';
                    final obscureKey = 'hist_$idx';
                    final isObscured = _isObscured(obscureKey);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isObscured ? '••••••••••••' : histPwd,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: isObscured ? AppTheme.textSecondaryColor : AppTheme.textPrimaryColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Rotated: ${hist.changedAt.toLocal().toString().split('.').first}',
                                  style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(isObscured ? Icons.visibility_off : Icons.visibility, color: AppTheme.textSecondaryColor, size: 18),
                            onPressed: () => _toggleObscure(obscureKey),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: AppTheme.primaryColor, size: 18),
                            onPressed: () => _copyToClipboard('Historical Password', histPwd),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeIcon(VaultItemType type) {
    IconData icon;
    Color color;
    switch (type) {
      case VaultItemType.login:
        icon = Icons.language;
        color = Colors.blueAccent;
        break;
      case VaultItemType.creditCard:
        icon = Icons.credit_card;
        color = Colors.purpleAccent;
        break;
      case VaultItemType.identity:
        icon = Icons.person_outline;
        color = Colors.tealAccent;
        break;
      case VaultItemType.secureNote:
        icon = Icons.note_outlined;
        color = Colors.amberAccent;
        break;
      case VaultItemType.bankAccount:
        icon = Icons.account_balance_outlined;
        color = Colors.lightBlueAccent;
        break;
      case VaultItemType.password:
        icon = Icons.vpn_key_outlined;
        color = AppTheme.primaryColor;
        break;
      case VaultItemType.totp:
        icon = Icons.qr_code_2_outlined;
        color = Colors.cyanAccent;
        break;
      case VaultItemType.sshKey:
        icon = Icons.terminal_outlined;
        color = Colors.orangeAccent;
        break;
      case VaultItemType.apiKey:
        icon = Icons.api_outlined;
        color = Colors.greenAccent;
        break;
      case VaultItemType.cryptoSeed:
        icon = Icons.currency_bitcoin;
        color = Colors.amber;
        break;
      case VaultItemType.softwareLicense:
        icon = Icons.card_membership_outlined;
        color = Colors.indigoAccent;
        break;
      case VaultItemType.passkey:
        icon = Icons.fingerprint;
        color = Colors.lightGreenAccent;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  List<Widget> _buildTypeFields(VaultItem item) {
    final fields = item.fields;
    if (fields is LoginFields) {
      return [
        _buildDetailField('Username', fields.username),
        _buildDetailField('Password', fields.password.plaintext ?? '', isSecret: true, obscureKey: 'login_pw'),
        if (fields.otpSecret.plaintext != null && fields.otpSecret.plaintext!.isNotEmpty)
          _buildDetailField('One-Time Password Secret', fields.otpSecret.plaintext!, isSecret: true, obscureKey: 'login_otp'),
        if (fields.urls.isNotEmpty)
          _buildDetailField('Websites', fields.urls.join(', ')),
      ];
    } else if (fields is CreditCardFields) {
      return [
        _buildDetailField('Cardholder Name', fields.cardholderName),
        _buildDetailField('Card Number', fields.cardNumber.plaintext ?? '', isSecret: true, obscureKey: 'cc_num'),
        _buildDetailField('Brand', fields.brand.toUpperCase()),
        _buildDetailField('Expiration', '${fields.expiryMonth.toString().padLeft(2, '0')}/${fields.expiryYear}'),
        _buildDetailField('CVV', fields.cvv.plaintext ?? '', isSecret: true, obscureKey: 'cc_cvv'),
        if (fields.pin.plaintext != null && fields.pin.plaintext!.isNotEmpty)
          _buildDetailField('PIN', fields.pin.plaintext ?? '', isSecret: true, obscureKey: 'cc_pin'),
      ];
    } else if (fields is IdentityFields) {
      return [
        _buildDetailField('First Name', fields.firstName),
        _buildDetailField('Last Name', fields.lastName),
        if (fields.birthdate != null) _buildDetailField('Birthdate', fields.birthdate!),
        if (fields.gender != null) _buildDetailField('Gender', fields.gender!),
        _buildDetailField('Address', '${fields.address.street}, ${fields.address.city}, ${fields.address.state} ${fields.address.zip}, ${fields.address.country}'),
        if (fields.emails.isNotEmpty) _buildDetailField('Emails', fields.emails.join(', ')),
        if (fields.phoneNumbers.isNotEmpty) _buildDetailField('Phone Numbers', fields.phoneNumbers.join(', ')),
      ];
    } else if (fields is SecureNoteFields) {
      return [
        _buildDetailField('Secure Note Content', fields.content.plaintext ?? '', isSecret: true, obscureKey: 'note_content'),
        if (fields.attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('ENCRYPTED FILE ATTACHMENTS', style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          ...fields.attachments.map((att) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.surfaceColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(att.fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('${att.mimeType} • ${(att.fileSize / 1024).toStringAsFixed(1)} KB', style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, size: 18, color: AppTheme.primaryColor),
                      onPressed: () => _copyToClipboard('Attachment Ciphertext', att.encryptedData.ciphertext ?? ''),
                      tooltip: 'Copy Encrypted Blob',
                    ),
                  ],
                ),
              )),
        ],
      ];
    } else if (fields is BankAccountFields) {
      return [
        _buildDetailField('Bank Name', fields.bankName),
        _buildDetailField('Account Type', fields.accountType.toUpperCase()),
        _buildDetailField('Account Number', fields.accountNumber.plaintext ?? '', isSecret: true, obscureKey: 'bank_acc'),
        _buildDetailField('Routing Number', fields.routingNumber.plaintext ?? '', isSecret: true, obscureKey: 'bank_rout'),
        if (fields.iban != null) _buildDetailField('IBAN', fields.iban!),
        if (fields.swift != null) _buildDetailField('SWIFT/BIC', fields.swift!),
      ];
    } else if (fields is PasswordFields) {
      return [
        _buildDetailField('Password', fields.password.plaintext ?? '', isSecret: true, obscureKey: 'pw_standalone'),
      ];
    } else if (fields is TotpFields) {
      return [
        TotpCodeCard.fromFields(fields: fields),
        const SizedBox(height: 12),
        _buildDetailField('Issuer / Service', fields.issuer),
        if (fields.accountName.isNotEmpty) _buildDetailField('Account Name', fields.accountName),
        _buildDetailField('Secret Key (Base32)', fields.secret.plaintext ?? '', isSecret: true, obscureKey: 'totp_secret'),
        _buildDetailField('Algorithm', fields.algorithm),
        _buildDetailField('Digits', fields.digits.toString()),
        _buildDetailField('Period', '${fields.period}s'),
      ];
    } else if (fields is SshKeyFields) {
      return [
        _buildDetailField('Key Name', fields.keyName),
        _buildDetailField('Key Type', fields.keyType),
        _buildDetailField('Private Key (PEM)', fields.privateKey.plaintext ?? '', isSecret: true, obscureKey: 'ssh_priv', isMonospace: true),
        if (fields.publicKey.isNotEmpty) _buildDetailField('Public Key (OpenSSH)', fields.publicKey, isMonospace: true),
        if (fields.passphrase.plaintext != null && fields.passphrase.plaintext!.isNotEmpty)
          _buildDetailField('Key Passphrase', fields.passphrase.plaintext!, isSecret: true, obscureKey: 'ssh_pass'),
      ];
    } else if (fields is ApiKeyFields) {
      return [
        _buildDetailField('Service Name', fields.serviceName),
        _buildDetailField('API Key / Token', fields.keyValue.plaintext ?? '', isSecret: true, obscureKey: 'api_key', isMonospace: true),
        if (fields.apiSecret.plaintext != null && fields.apiSecret.plaintext!.isNotEmpty)
          _buildDetailField('API Secret', fields.apiSecret.plaintext!, isSecret: true, obscureKey: 'api_sec', isMonospace: true),
        if (fields.expiryDate != null) _buildDetailField('Expiration Date', fields.expiryDate!),
        if (fields.notes != null) _buildDetailField('Notes', fields.notes!),
      ];
    } else if (fields is CryptoSeedFields) {
      return [
        _buildDetailField('Wallet Name', fields.walletName),
        _buildDetailField(
          'Seed Phrase (Mnemonic)',
          fields.seedPhrase.plaintext ?? '',
          isSecret: true,
          obscureKey: 'crypto_seed',
          isMonospace: true,
          isMaximallySensitive: true,
        ),
        if (fields.derivationPath != null) _buildDetailField('Derivation Path', fields.derivationPath!, isMonospace: true),
        if (fields.notes != null) _buildDetailField('Notes', fields.notes!),
      ];
    } else if (fields is SoftwareLicenseFields) {
      return [
        _buildDetailField('Product Name', fields.productName),
        _buildDetailField('License Key', fields.licenseKey.plaintext ?? '', isSecret: true, obscureKey: 'license_key', isMonospace: true),
        if (fields.purchaseDate != null) _buildDetailField('Purchase Date', fields.purchaseDate!),
        if (fields.seatsOrVersion != null) _buildDetailField('Seats / Version', fields.seatsOrVersion!),
        if (fields.vendor != null) _buildDetailField('Publisher / Vendor', fields.vendor!),
      ];
    }
    return const [];
  }

  Widget _buildDetailField(
    String label,
    String value, {
    bool isSecret = false,
    String? obscureKey,
    bool isMonospace = false,
    bool isMaximallySensitive = false,
  }) {
    if (value.isEmpty) return const SizedBox.shrink();
    final obscured = isSecret && obscureKey != null && _isObscured(obscureKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 12)),
              if (isMaximallySensitive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'MAX SENSITIVE',
                    style: TextStyle(color: AppTheme.errorColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  obscured ? '••••••••••••••••' : value,
                  style: TextStyle(
                    fontFamily: obscured ? null : (isMonospace ? 'monospace' : 'Inter'),
                    fontSize: 14,
                    fontWeight: obscured ? FontWeight.bold : FontWeight.w500,
                    letterSpacing: obscured ? 2.0 : 0.0,
                  ),
                ),
              ),
              if (isSecret && obscureKey != null)
                IconButton(
                  icon: Icon(obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: () {
                    if (isMaximallySensitive && obscured) {
                      _showSensitiveRevealDialog(label, obscureKey);
                    } else {
                      _toggleObscure(obscureKey);
                    }
                  },
                  tooltip: obscured ? 'Reveal' : 'Mask',
                ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18, color: AppTheme.primaryColor),
                onPressed: () => _copyToClipboard(label, value),
                tooltip: 'Copy to Clipboard',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSensitiveRevealDialog(String label, String obscureKey) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor),
            SizedBox(width: 8),
            Text('Security Alert'),
          ],
        ),
        content: Text(
          'You are about to reveal $label.\n\nEnsure no one is looking over your shoulder or recording your screen before confirming.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              _toggleObscure(obscureKey);
            },
            child: const Text('Confirm & Reveal'),
          ),
        ],
      ),
    );
  }
}
