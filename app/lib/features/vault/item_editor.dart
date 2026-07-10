import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';

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
              title: const Text('Add Custom Field'),
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
                    value: type,
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
                  child: const Text('Cancel'),
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
    }

    final tags = _tagsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final item = VaultItem(
      id: widget.item?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: _selectedType!,
      title: _titleController.text,
      tags: tags,
      favorite: _favorite,
      vaultId: widget.item?.vaultId ?? '',
      createdAt: widget.item?.createdAt ?? DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      fields: fields,
      customFields: _customFields,
      notes: ConcealedValue.plain(_notesController.text),
    );

    // Encrypt under the vault key
    final encryptedItem = await item.encrypt(widget.vaultKey, _crypto);
    widget.onSave(encryptedItem);
    Navigator.of(context).pop();
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
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Shared Core Info
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),

            // Type-Specific Subforms
            ..._buildTypeSpecificForms(),

            const Divider(color: Colors.white10, height: 40),
            const Text(
              'ADDITIONAL METADATA',
              style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
            const SizedBox(height: 16),

            // Tags
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.description_outlined),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            // Favorite Toggle
            CheckboxListTile(
              title: const Text('Add to Favorites'),
              value: _favorite,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _favorite = val);
                }
              },
            ),

            // Custom fields list & addition
            if (_customFields.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Custom Fields:', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._customFields.map((cf) => ListTile(
                    title: Text(cf.label),
                    subtitle: Text(cf.type == 'concealed' ? '••••••••' : (cf.value.plaintext ?? '')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                      onPressed: () => setState(() => _customFields.remove(cf)),
                    ),
                  )),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: const BorderSide(color: AppTheme.primaryColor),
              ),
              onPressed: _addCustomField,
              icon: const Icon(Icons.add),
              label: const Text('Add Custom Field'),
            ),
            const SizedBox(height: 40),
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
        ],
      ),
    );
  }

  Widget _buildTypeTile(VaultItemType type, String label, IconData icon, Color color) {
    return Card(
      color: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedType = type),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
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
          const SizedBox(height: 16),
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
                    icon: const Icon(Icons.autorenew),
                    onPressed: _generateAndSetPassword,
                    tooltip: 'Generate secure password',
                  ),
                ],
              ),
            ),
            validator: (v) => v == null || v.isEmpty ? 'Password is required' : null,
          ),
          const SizedBox(height: 12),
          // Password Strength Meter integration
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
          const SizedBox(height: 20),

          // Websites (Add Multiple)
          const Text(
            'WEBSITE URLS',
            style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
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
                    hintText: 'e.g. https://google.com',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('add-url-button'),
                icon: const Icon(Icons.add, color: AppTheme.primaryColor),
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
          const SizedBox(height: 20),

          // One-Time Password (OTP) Setup
          const Text(
            'ONE-TIME PASSWORD (TOTP)',
            style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
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
                icon: const Icon(Icons.qr_code_scanner_rounded),
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
        ];
      case VaultItemType.creditCard:
        return [
          const SizedBox(height: 16),
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
            value: _ccBrand,
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
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            key: const Key('cc-billing-address-dropdown'),
            value: _ccBillingAddressRef,
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
        ];
      case VaultItemType.identity:
        return [
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
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
        ];
      case VaultItemType.secureNote:
        return [
          const SizedBox(height: 16),
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
        ];
      case VaultItemType.bankAccount:
        return [
          const SizedBox(height: 16),
          TextFormField(
            controller: _bankNameController,
            decoration: const InputDecoration(labelText: 'Bank Name', prefixIcon: Icon(Icons.account_balance)),
            validator: (v) => v == null || v.isEmpty ? 'Bank name is required' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _bankAccType,
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
        ];
      case VaultItemType.password:
        return [
          const SizedBox(height: 16),
          TextFormField(
            controller: _standalonePwController,
            obscureText: _obscureStandalonePw,
            decoration: InputDecoration(
              labelText: 'Secret Password',
              prefixIcon: const Icon(Icons.vpn_key),
              suffixIcon: IconButton(
                icon: Icon(_obscureStandalonePw ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscureStandalonePw = !_obscureStandalonePw),
              ),
            ),
            validator: (v) => v == null || v.isEmpty ? 'Password is required' : null,
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
              color: AppTheme.errorColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.errorColor.withOpacity(0.15)),
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
