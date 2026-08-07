import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:uuid/uuid.dart';
import '../../theme/theme.dart';
import 'sharing/pqc_sharing_service.dart';

class ItemEditorScreen extends StatefulWidget {
  final VaultItem? item;
  final List<int> vaultKey;
  final VaultDatabase db;
  final Function(EncryptedVaultItem encryptedItem) onSave;

  const ItemEditorScreen({
    super.key,
    this.item,
    required this.vaultKey,
    required this.db,
    required this.onSave,
  });

  @override
  State<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends State<ItemEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _crypto = VaultCrypto();

  VaultItemType? _selectedType;
  List<VaultItem> _identities = [];
  String? _ccBillingAddressRef;

  // Visibility states
  bool _obscureCcNum = true;
  bool _obscureCcCvv = true;
  bool _obscureCcPin = true;
  bool _obscureBankAcc = true;
  bool _obscureBankRouting = true;
  bool _obscureNote = true;
  bool _obscureStandalonePw = true;
  bool _isEditing = false;

  // Shared Fields
  final _titleController = TextEditingController();
  final _tagsController = TextEditingController();
  final _folderController = TextEditingController();
  final _notesController = TextEditingController();
  bool _favorite = false;
  final List<CustomField> _customFields = [];

  // Type Specific Controllers
  // Login
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _urlInputController = TextEditingController();
  final List<String> _urls = [];
  bool _obscureLoginPw = true;

  // Credit Card
  final _ccHolderController = TextEditingController();
  final _ccNumController = TextEditingController();
  String _ccBrand = 'visa';
  int _ccExpiryMonth = 1;
  int _ccExpiryYear = 2026;
  final _ccCvvController = TextEditingController();
  final _ccPinController = TextEditingController();

  // Identity
  final _idFirstNameController = TextEditingController();
  final _idLastNameController = TextEditingController();
  final _idBirthdateController = TextEditingController();
  final _idGenderController = TextEditingController();
  final _idStreetController = TextEditingController();
  final _idCityController = TextEditingController();
  final _idStateController = TextEditingController();
  final _idZipController = TextEditingController();
  final _idCountryController = TextEditingController();
  final List<String> _idEmails = [];
  final List<String> _idPhones = [];

  // Secure Note
  final _noteContentController = TextEditingController();

  // Bank Account
  final _bankNameController = TextEditingController();
  String _bankAccType = 'checking';
  final _bankAccNumController = TextEditingController();
  final _bankRoutingController = TextEditingController();
  final _bankIbanController = TextEditingController();
  final _bankSwiftController = TextEditingController();

  // Standalone Password
  final _standalonePwController = TextEditingController();

  // TOTP / Authenticator
  final _totpIssuerController = TextEditingController();
  final _totpAccountController = TextEditingController();
  final _totpSecretController = TextEditingController();
  final _totpUriInputController = TextEditingController();
  String _totpAlgorithm = 'SHA1';
  int _totpDigits = 6;
  int _totpPeriod = 30;
  bool _obscureTotpSecret = true;

  @override
  void initState() {
    super.initState();
    _loadIdentities();
    if (widget.item != null) {
      _isEditing = true;
      _selectedType = widget.item!.type;
      _populateFromItem(widget.item!);
    }
  }

  Future<void> _loadIdentities() async {
    final encItems = widget.db.getAllItems();
    final List<VaultItem> list = [];
    for (final enc in encItems) {
      if (enc.isDeleted) continue;
      try {
        final dec = await VaultItem.decrypt(enc, widget.vaultKey, _crypto);
        if (dec.type == VaultItemType.identity) {
          list.add(dec);
        }
      } catch (_) {}
    }
    setState(() {
      _identities = list;
    });
  }

  void _populateFromItem(VaultItem item) {
    _titleController.text = item.title;
    _tagsController.text = item.tags.join(', ');
    _folderController.text = item.vaultId;
    _notesController.text = item.notes.plaintext ?? '';
    _favorite = item.favorite;
    _customFields.addAll(item.customFields);

    final fields = item.fields;
    if (fields is LoginFields) {
      _usernameController.text = fields.username;
      _passwordController.text = fields.password.plaintext ?? '';
      _otpController.text = fields.otpSecret.plaintext ?? '';
      _urls.addAll(fields.urls);
    } else if (fields is CreditCardFields) {
      _ccHolderController.text = fields.cardholderName;
      _ccNumController.text = fields.cardNumber.plaintext ?? '';
      _ccBrand = fields.brand;
      _ccExpiryMonth = fields.expiryMonth;
      _ccExpiryYear = fields.expiryYear;
      _ccCvvController.text = fields.cvv.plaintext ?? '';
      _ccPinController.text = fields.pin.plaintext ?? '';
      _ccBillingAddressRef = fields.billingAddressRef;
    } else if (fields is IdentityFields) {
      _idFirstNameController.text = fields.firstName;
      _idLastNameController.text = fields.lastName;
      _idBirthdateController.text = fields.birthdate ?? '';
      _idGenderController.text = fields.gender ?? '';
      _idStreetController.text = fields.address.street;
      _idCityController.text = fields.address.city;
      _idStateController.text = fields.address.state;
      _idZipController.text = fields.address.zip;
      _idCountryController.text = fields.address.country;
      _idEmails.addAll(fields.emails);
      _idPhones.addAll(fields.phoneNumbers);
    } else if (fields is SecureNoteFields) {
      _noteContentController.text = fields.content.plaintext ?? '';
    } else if (fields is BankAccountFields) {
      _bankNameController.text = fields.bankName;
      _bankAccType = fields.accountType;
      _bankAccNumController.text = fields.accountNumber.plaintext ?? '';
      _bankRoutingController.text = fields.routingNumber.plaintext ?? '';
      _bankIbanController.text = fields.iban ?? '';
      _bankSwiftController.text = fields.swift ?? '';
    } else if (fields is PasswordFields) {
      _standalonePwController.text = fields.password.plaintext ?? '';
    } else if (fields is TotpFields) {
      _totpIssuerController.text = fields.issuer;
      _totpAccountController.text = fields.accountName;
      _totpSecretController.text = fields.secret.plaintext ?? '';
      _totpAlgorithm = fields.algorithm;
      _totpDigits = fields.digits;
      _totpPeriod = fields.period;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _ccHolderController.dispose();
    _ccNumController.dispose();
    _ccCvvController.dispose();
    _ccPinController.dispose();
    _idFirstNameController.dispose();
    _idLastNameController.dispose();
    _idBirthdateController.dispose();
    _idGenderController.dispose();
    _idStreetController.dispose();
    _idCityController.dispose();
    _idStateController.dispose();
    _idZipController.dispose();
    _idCountryController.dispose();
    _noteContentController.dispose();
    _bankNameController.dispose();
    _bankAccNumController.dispose();
    _bankRoutingController.dispose();
    _bankIbanController.dispose();
    _bankSwiftController.dispose();
    _totpIssuerController.dispose();
    _totpAccountController.dispose();
    _totpSecretController.dispose();
    _totpUriInputController.dispose();
    _standalonePwController.dispose();
    _urlInputController.dispose();
    super.dispose();
  }

  void _addCustomField() {
    String label = '';
    String value = '';
    String type = 'text';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Add Custom Field', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: 'Field Label'),
                    onChanged: (val) => label = val,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(labelText: 'Field Value'),
                    onChanged: (val) => value = val,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('Plain Text')),
                      DropdownMenuItem(value: 'concealed', child: Text('Concealed (Secret)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDlgState(() => type = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondaryColor)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (label.isNotEmpty) {
                      setState(() {
                        _customFields.add(CustomField(
                          label: label,
                          type: type,
                          value: ConcealedValue.plain(value),
                        ));
                      });
                      Navigator.of(ctx).pop();
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _selectedType == null) return;

    VaultItemFields fields;
    switch (_selectedType!) {
      case VaultItemType.login:
        fields = LoginFields(
          username: _usernameController.text,
          password: ConcealedValue.plain(_passwordController.text),
          urls: _urls,
          otpSecret: ConcealedValue.plain(_otpController.text),
          passwordHistory: const [],
        );
        break;
      case VaultItemType.creditCard:
        fields = CreditCardFields(
          cardholderName: _ccHolderController.text,
          cardNumber: ConcealedValue.plain(_ccNumController.text),
          brand: _ccBrand,
          expiryMonth: _ccExpiryMonth,
          expiryYear: _ccExpiryYear,
          cvv: ConcealedValue.plain(_ccCvvController.text),
          pin: ConcealedValue.plain(_ccPinController.text),
          billingAddressRef: _ccBillingAddressRef,
        );
        break;
      case VaultItemType.identity:
        fields = IdentityFields(
          firstName: _idFirstNameController.text,
          lastName: _idLastNameController.text,
          birthdate: _idBirthdateController.text.isNotEmpty ? _idBirthdateController.text : null,
          gender: _idGenderController.text.isNotEmpty ? _idGenderController.text : null,
          address: IdentityAddress(
            street: _idStreetController.text,
            city: _idCityController.text,
            state: _idStateController.text,
            zip: _idZipController.text,
            country: _idCountryController.text,
          ),
          emails: _idEmails,
          phoneNumbers: _idPhones,
        );
        break;
      case VaultItemType.secureNote:
        fields = SecureNoteFields(
          content: ConcealedValue.plain(_noteContentController.text),
        );
        break;
      case VaultItemType.bankAccount:
        fields = BankAccountFields(
          bankName: _bankNameController.text,
          accountType: _bankAccType,
          accountNumber: ConcealedValue.plain(_bankAccNumController.text),
          routingNumber: ConcealedValue.plain(_bankRoutingController.text),
          iban: _bankIbanController.text.isNotEmpty ? _bankIbanController.text : null,
          swift: _bankSwiftController.text.isNotEmpty ? _bankSwiftController.text : null,
        );
        break;
      case VaultItemType.password:
        fields = PasswordFields(
          password: ConcealedValue.plain(_standalonePwController.text),
        );
        break;
      case VaultItemType.totp:
        fields = TotpFields(
          issuer: _totpIssuerController.text,
          accountName: _totpAccountController.text,
          secret: ConcealedValue.plain(_totpSecretController.text),
          algorithm: _totpAlgorithm,
          digits: _totpDigits,
          period: _totpPeriod,
        );
        break;
    }

    final tags = _tagsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final folderText = _folderController.text.trim();
    final targetVaultId = folderText.isNotEmpty
        ? getFolderUuid(folderText)
        : (widget.item?.vaultId.isNotEmpty == true ? getFolderUuid(widget.item!.vaultId) : '');

    final item = VaultItem(
      id: widget.item?.id ?? const Uuid().v4(),
      type: _selectedType!,
      title: _titleController.text,
      tags: tags,
      favorite: _favorite,
      vaultId: targetVaultId,
      createdAt: widget.item?.createdAt ?? DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      fields: fields,
      customFields: _customFields,
      notes: ConcealedValue.plain(_notesController.text),
    );

    List<int> encryptionKey = widget.vaultKey;
    if (targetVaultId.isNotEmpty) {
      if (PqcSharingService.unwrappedFolderKeys.containsKey(targetVaultId)) {
        encryptionKey = PqcSharingService.unwrappedFolderKeys[targetVaultId]!;
      } else {
        encryptionKey = deriveFolderKey(widget.vaultKey, targetVaultId);
        PqcSharingService.unwrappedFolderKeys[targetVaultId] = Uint8List.fromList(encryptionKey);
      }
    }

    final encryptedItem = await item.encrypt(encryptionKey, _crypto);
    widget.onSave(encryptedItem);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildSectionCard({
    required String title,
    IconData? titleIcon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                if (titleIcon != null) ...[
                  Icon(titleIcon, size: 16, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                ],
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedType == null) {
      return _buildTypePicker();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Item' : 'Add Item'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: AppTheme.primaryColor),
            onPressed: _save,
            tooltip: 'Save Item',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Core Overview Section
            _buildSectionCard(
              title: 'Item Details',
              titleIcon: Icons.title,
              children: [
                TextFormField(
                  controller: _titleController,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. GitHub, Personal Visa, Master Password',
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Title is required' : null,
                ),
              ],
            ),

            // Type-Specific Sections
            ..._buildTypeSpecificForms(),

            // Additional Metadata & Notes Section
            _buildSectionCard(
              title: 'Organization & Notes',
              titleIcon: Icons.folder_outlined,
              children: [
                TextFormField(
                  controller: _folderController,
                  decoration: const InputDecoration(
                    labelText: 'Folder / Shared Section Name or ID (optional)',
                    hintText: 'e.g. sdvdlvkndl, nvskjndvs',
                    prefixIcon: Icon(Icons.folder_open_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags (comma separated)',
                    hintText: 'work, personal, banking',
                    prefixIcon: Icon(Icons.tag_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Secure notes or additional hints',
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    title: const Text('Add to Favorites', style: TextStyle(fontSize: 14)),
                    value: _favorite,
                    activeColor: AppTheme.primaryColor,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _favorite = val);
                      }
                    },
                  ),
                ),
                if (_customFields.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'CUSTOM FIELDS',
                    style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 8),
                  ..._customFields.map((cf) => ListTile(
                        title: Text(cf.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: Text(cf.type == 'concealed' ? '••••••••' : (cf.value.plaintext ?? '')),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                          onPressed: () => setState(() => _customFields.remove(cf)),
                        ),
                        contentPadding: EdgeInsets.zero,
                      )),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(color: AppTheme.primaryColor),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _addCustomField,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Custom Field'),
                ),
              ],
            ),

            const SizedBox(height: 12),
            // Primary Submit Button at bottom
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.lock_outlined),
              label: Text(
                _isEditing ? 'Save Changes' : 'Save Vault Item',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: _save,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTypePicker() {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Item Type')),
      body: GridView.count(
        padding: const EdgeInsets.all(24),
        crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        children: [
          _buildTypeTile(VaultItemType.login, 'Login', Icons.language, Colors.blueAccent),
          _buildTypeTile(VaultItemType.creditCard, 'Credit Card', Icons.credit_card, Colors.purpleAccent),
          _buildTypeTile(VaultItemType.identity, 'Identity', Icons.person_outline, Colors.tealAccent),
          _buildTypeTile(VaultItemType.secureNote, 'Secure Note', Icons.note_outlined, Colors.amberAccent),
          _buildTypeTile(VaultItemType.bankAccount, 'Bank Account', Icons.account_balance_outlined, Colors.lightBlueAccent),
          _buildTypeTile(VaultItemType.password, 'Password', Icons.vpn_key_outlined, AppTheme.primaryColor),
          _buildTypeTile(VaultItemType.totp, 'TOTP / 2FA', Icons.qr_code_2_outlined, Colors.cyanAccent),
        ],
      ),
    );
  }

  Widget _buildTypeTile(VaultItemType type, String label, IconData icon, Color color) {
    return Card(
      color: AppTheme.surfaceColor,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedType = type),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  void _generateAndSetPassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()_+~`|}{[]:;?><,./-=';
    final bytes = _crypto.generateRandomBytes(16);
    final generated = bytes.map((b) => chars[b % chars.length]).join();
    setState(() {
      _passwordController.text = generated;
    });
  }

  List<Widget> _buildTypeSpecificForms() {
    switch (_selectedType!) {
      case VaultItemType.login:
        return [
          _buildSectionCard(
            title: 'Credentials',
            titleIcon: Icons.key_outlined,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username / Email',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Username is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('password-field'),
                controller: _passwordController,
                obscureText: _obscureLoginPw,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(_obscureLoginPw ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscureLoginPw = !_obscureLoginPw),
                        tooltip: 'Toggle visibility',
                      ),
                      IconButton(
                        key: const Key('generate-button'),
                        icon: const Icon(Icons.autorenew, color: AppTheme.primaryColor),
                        onPressed: _generateAndSetPassword,
                        tooltip: 'Generate secure password',
                      ),
                    ],
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Password is required' : null,
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: _passwordController,
                builder: (context, _) {
                  return PasswordStrengthMeter(
                    password: _passwordController.text,
                    userInputs: [
                      _usernameController.text,
                      _titleController.text,
                    ],
                  );
                },
              ),
            ],
          ),

          _buildSectionCard(
            title: 'Website URLs',
            titleIcon: Icons.language,
            children: [
              if (_urls.isNotEmpty) ...[
                ..._urls.map((url) => ListTile(
                      title: Text(url, style: const TextStyle(fontSize: 13)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorColor),
                        onPressed: () => setState(() => _urls.remove(url)),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    )),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _urlInputController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. https://github.com',
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('add-url-button'),
                    icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor, size: 28),
                    onPressed: () {
                      final url = _urlInputController.text.trim();
                      if (url.isNotEmpty) {
                        setState(() {
                          _urls.add(url);
                          _urlInputController.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),

          _buildSectionCard(
            title: 'One-Time Password (TOTP)',
            titleIcon: Icons.timer_outlined,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _otpController,
                      decoration: const InputDecoration(
                        labelText: 'TOTP Secret Key',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('scan-qr-button'),
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primaryColor),
                    onPressed: () {
                      setState(() {
                        _otpController.text = 'JBSWY3DPEHPK3PXP';
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mock QR Code scanned successfully')),
                      );
                    },
                    tooltip: 'Scan QR Code (Mock)',
                  ),
                ],
              ),
            ],
          ),
        ];

      case VaultItemType.creditCard:
        return [
          _buildSectionCard(
            title: 'Card Details',
            titleIcon: Icons.credit_card,
            children: [
              TextFormField(
                controller: _ccHolderController,
                decoration: const InputDecoration(
                  labelText: 'Cardholder Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Cardholder name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('cc-number-field'),
                controller: _ccNumController,
                obscureText: _obscureCcNum,
                decoration: InputDecoration(
                  labelText: 'Card Number',
                  prefixIcon: const Icon(Icons.credit_card),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureCcNum ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscureCcNum = !_obscureCcNum),
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Card number is required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _ccBrand,
                decoration: const InputDecoration(labelText: 'Brand'),
                items: const [
                  DropdownMenuItem(value: 'visa', child: Text('Visa')),
                  DropdownMenuItem(value: 'mastercard', child: Text('Mastercard')),
                  DropdownMenuItem(value: 'amex', child: Text('Amex')),
                  DropdownMenuItem(value: 'discover', child: Text('Discover')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _ccBrand = val);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ccCvvController,
                      obscureText: _obscureCcCvv,
                      decoration: InputDecoration(
                        labelText: 'CVV',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCcCvv ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscureCcCvv = !_obscureCcCvv),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _ccPinController,
                      obscureText: _obscureCcPin,
                      decoration: InputDecoration(
                        labelText: 'PIN',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCcPin ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscureCcPin = !_obscureCcPin),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          _buildSectionCard(
            title: 'Billing Link',
            titleIcon: Icons.home_outlined,
            children: [
              DropdownButtonFormField<String?>(
                key: const Key('cc-billing-address-dropdown'),
                initialValue: _ccBillingAddressRef,
                decoration: const InputDecoration(
                  labelText: 'Link Billing Address (Identity)',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None (Use Default)'),
                  ),
                  ..._identities.map((idItem) {
                    final idFields = idItem.fields as IdentityFields;
                    return DropdownMenuItem<String?>(
                      value: idItem.id,
                      child: Text('${idItem.title} (${idFields.firstName} ${idFields.lastName})'),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _ccBillingAddressRef = val;
                  });
                },
              ),
            ],
          ),
        ];

      case VaultItemType.identity:
        return [
          _buildSectionCard(
            title: 'Personal Profile',
            titleIcon: Icons.person_outline,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _idFirstNameController,
                      decoration: const InputDecoration(labelText: 'First Name'),
                      validator: (v) => v == null || v.isEmpty ? 'First name is required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _idLastNameController,
                      decoration: const InputDecoration(labelText: 'Last Name'),
                      validator: (v) => v == null || v.isEmpty ? 'Last name is required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idBirthdateController,
                decoration: const InputDecoration(labelText: 'Birthdate (YYYY-MM-DD)', prefixIcon: Icon(Icons.cake_outlined)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idGenderController,
                decoration: const InputDecoration(labelText: 'Gender'),
              ),
            ],
          ),

          _buildSectionCard(
            title: 'Address',
            titleIcon: Icons.home_outlined,
            children: [
              TextFormField(
                controller: _idStreetController,
                decoration: const InputDecoration(labelText: 'Street Address', prefixIcon: Icon(Icons.home_outlined)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _idCityController,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _idStateController,
                      decoration: const InputDecoration(labelText: 'State/Province'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _idZipController,
                      decoration: const InputDecoration(labelText: 'Zip/Postal Code'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _idCountryController,
                      decoration: const InputDecoration(labelText: 'Country'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ];

      case VaultItemType.secureNote:
        return [
          _buildSectionCard(
            title: 'Secure Note Content',
            titleIcon: Icons.note_outlined,
            children: [
              TextFormField(
                controller: _noteContentController,
                obscureText: _obscureNote,
                maxLines: _obscureNote ? 1 : 6,
                decoration: InputDecoration(
                  labelText: 'Secure Content',
                  alignLabelWithHint: true,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNote ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscureNote = !_obscureNote),
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Secure content is required' : null,
              ),
            ],
          ),
        ];

      case VaultItemType.bankAccount:
        return [
          _buildSectionCard(
            title: 'Bank & Account Details',
            titleIcon: Icons.account_balance_outlined,
            children: [
              TextFormField(
                controller: _bankNameController,
                decoration: const InputDecoration(labelText: 'Bank Name', prefixIcon: Icon(Icons.account_balance)),
                validator: (v) => v == null || v.isEmpty ? 'Bank name is required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _bankAccType,
                decoration: const InputDecoration(labelText: 'Account Type'),
                items: const [
                  DropdownMenuItem(value: 'checking', child: Text('Checking')),
                  DropdownMenuItem(value: 'savings', child: Text('Savings')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _bankAccType = val);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bankAccNumController,
                obscureText: _obscureBankAcc,
                decoration: InputDecoration(
                  labelText: 'Account Number',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureBankAcc ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscureBankAcc = !_obscureBankAcc),
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Account number is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bankRoutingController,
                obscureText: _obscureBankRouting,
                decoration: InputDecoration(
                  labelText: 'Routing Number',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureBankRouting ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscureBankRouting = !_obscureBankRouting),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bankIbanController,
                decoration: const InputDecoration(labelText: 'IBAN'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bankSwiftController,
                decoration: const InputDecoration(labelText: 'SWIFT/BIC'),
              ),
            ],
          ),
        ];

      case VaultItemType.password:
        return [
          _buildSectionCard(
            title: 'Standalone Secret',
            titleIcon: Icons.vpn_key_outlined,
            children: [
              TextFormField(
                controller: _standalonePwController,
                obscureText: _obscureStandalonePw,
                decoration: InputDecoration(
                  labelText: 'Secret Password',
                  prefixIcon: const Icon(Icons.vpn_key),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(_obscureStandalonePw ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscureStandalonePw = !_obscureStandalonePw),
                      ),
                      IconButton(
                        icon: const Icon(Icons.autorenew, color: AppTheme.primaryColor),
                        onPressed: () {
                          const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';
                          final bytes = _crypto.generateRandomBytes(16);
                          final generated = bytes.map((b) => chars[b % chars.length]).join();
                          setState(() {
                            _standalonePwController.text = generated;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Password is required' : null,
              ),
            ],
          ),
        ];

      case VaultItemType.totp:
        return [
          _buildSectionCard(
            title: 'Import from otpauth:// URI',
            titleIcon: Icons.qr_code_scanner,
            children: [
              TextFormField(
                controller: _totpUriInputController,
                decoration: InputDecoration(
                  labelText: 'Paste otpauth:// URI or secret',
                  hintText: 'otpauth://totp/GitHub:user@example.com?secret=JBSWY3DPEHPK3PXP',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.download, color: AppTheme.primaryColor),
                    tooltip: 'Parse URI',
                    onPressed: () {
                      final input = _totpUriInputController.text.trim();
                      if (input.isNotEmpty) {
                        try {
                          final params = TotpHelper.parseOtpauthUri(input);
                          setState(() {
                            if (params.issuer.isNotEmpty) _totpIssuerController.text = params.issuer;
                            if (params.accountName.isNotEmpty) _totpAccountController.text = params.accountName;
                            if (params.secret.isNotEmpty) _totpSecretController.text = params.secret;
                            _totpAlgorithm = params.algorithm;
                            _totpDigits = params.digits;
                            _totpPeriod = params.period;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('URI parsed successfully!')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Parse error: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'TOTP Secret & Parameters',
            titleIcon: Icons.security,
            children: [
              TextFormField(
                controller: _totpIssuerController,
                decoration: const InputDecoration(
                  labelText: 'Service / Issuer',
                  hintText: 'e.g. GitHub, Google, AWS',
                  prefixIcon: Icon(Icons.business),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Issuer is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _totpAccountController,
                decoration: const InputDecoration(
                  labelText: 'Account Name / Email',
                  hintText: 'e.g. user@example.com',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _totpSecretController,
                obscureText: _obscureTotpSecret,
                decoration: InputDecoration(
                  labelText: 'Base32 Secret Key',
                  hintText: 'e.g. JBSWY3DPEHPK3PXP',
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureTotpSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscureTotpSecret = !_obscureTotpSecret),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Secret key is required';
                  try {
                    TotpHelper.decodeBase32(v);
                  } catch (_) {
                    return 'Invalid Base32 secret key format';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _totpAlgorithm,
                      decoration: const InputDecoration(labelText: 'Algorithm'),
                      items: const [
                        DropdownMenuItem(value: 'SHA1', child: Text('SHA-1')),
                        DropdownMenuItem(value: 'SHA256', child: Text('SHA-256')),
                        DropdownMenuItem(value: 'SHA512', child: Text('SHA-512')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _totpAlgorithm = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _totpDigits,
                      decoration: const InputDecoration(labelText: 'Digits'),
                      items: const [
                        DropdownMenuItem(value: 6, child: Text('6 Digits')),
                        DropdownMenuItem(value: 8, child: Text('8 Digits')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _totpDigits = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _totpPeriod,
                      decoration: const InputDecoration(labelText: 'Period'),
                      items: const [
                        DropdownMenuItem(value: 30, child: Text('30s')),
                        DropdownMenuItem(value: 60, child: Text('60s')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _totpPeriod = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ];
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
        Row(
          children: List.generate(4, (index) {
            final barScore = index + 1;
            final isFilled = score >= barScore || (score == 0 && index == 0 && password.isNotEmpty);
            final barColor = isFilled ? color : Colors.grey[800]!;

            return Expanded(
              child: Container(
                height: 5,
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
            Text(
              password.isEmpty ? 'No Password Entered' : 'Strength: ${_getScoreText(score)}',
              style: TextStyle(
                color: password.isEmpty ? Colors.grey : color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            if (password.isNotEmpty)
              Text(
                'Crack time: ${result.estimatedCrackTime}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        if (password.isNotEmpty && result.suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.suggestions.map((suggestion) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 14, color: AppTheme.warningColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          suggestion,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textPrimaryColor),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
