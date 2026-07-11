import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';
import '../settings/settings_screen.dart';
import 'sharing/sharing_screen.dart';


class ItemDetailPane extends StatefulWidget {
  final VaultItem? item;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const ItemDetailPane({
    super.key,
    required this.item,
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
        title: Text(item.title, style: const TextStyle(fontFamily: 'Outfit')),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.teal),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SharingScreen(
                    folderId: item.id,
                    folderName: item.title,
                    currentFolderKey: Uint8List.fromList(List.generate(32, (i) => i)),
                    senderUserId: 'current-user-alice',
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
                color: AppTheme.warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warningColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 16),
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

          // Shared Header
          Row(
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
                        letterSpacing: 1.0,
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
          const SizedBox(height: 24),

          // Type specific fields
          ..._buildTypeFields(item),

          // Custom Fields Section
          if (item.customFields.isNotEmpty) ...[
            const Divider(color: Colors.white10, height: 40),
            const Text(
              'CUSTOM FIELDS',
              style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
            const SizedBox(height: 16),
            ...item.customFields.map((cf) => _buildDetailField(
                  cf.label,
                  cf.value.plaintext ?? '',
                  isSecret: cf.type == 'concealed',
                  obscureKey: 'cf_${cf.label}',
                )),
          ],

          // Notes Section
          if (item.notes.plaintext != null && item.notes.plaintext!.isNotEmpty) ...[
            const Divider(color: Colors.white10, height: 40),
            const Text(
              'NOTES',
              style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Text(
                item.notes.plaintext!,
                style: const TextStyle(height: 1.5, fontSize: 13),
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
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
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
    }
    return const [];
  }

  Widget _buildDetailField(String label, String value, {bool isSecret = false, String? obscureKey}) {
    if (value.isEmpty) return const SizedBox.shrink();
    final obscured = isSecret && obscureKey != null && _isObscured(obscureKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondaryColor, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  obscured ? '••••••••••••••••' : value,
                  style: TextStyle(
                    fontFamily: obscured ? null : 'Inter',
                    fontSize: 15,
                    fontWeight: obscured ? FontWeight.bold : FontWeight.normal,
                    letterSpacing: obscured ? 2.0 : 0.0,
                  ),
                ),
              ),
              if (isSecret && obscureKey != null)
                IconButton(
                  icon: Icon(obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: () => _toggleObscure(obscureKey),
                  tooltip: obscured ? 'Reveal' : 'Mask',
                ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () => _copyToClipboard(label, value),
                tooltip: 'Copy to Clipboard',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
