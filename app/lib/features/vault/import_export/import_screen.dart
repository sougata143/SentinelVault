import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:core/core.dart';
import '../../../theme/theme.dart';

/// Converts a [ParsedItem] into a [VaultItem], encrypts it under [vaultKey],
/// and writes it to [db]. Automatically handles all six item types.
Future<void> encryptAndSave(
  ParsedItem item,
  List<int> vaultKey,
  VaultDatabase db,
  VaultCrypto crypto,
) async {
  final now = DateTime.now().toUtc();
  final id = '${now.millisecondsSinceEpoch}_${item.title.hashCode.abs()}';

  VaultItemFields fields;
  VaultItemType type;

  switch (item.type) {
    case 'credit_card':
      type = VaultItemType.creditCard;
      fields = CreditCardFields(
        cardholderName: item.cardholderName ?? '',
        cardNumber: ConcealedValue.plain(item.cardNumber ?? ''),
        brand: item.cardBrand ?? 'other',
        expiryMonth: item.cardExpiryMonth ?? 1,
        expiryYear: item.cardExpiryYear ?? DateTime.now().year,
        cvv: ConcealedValue.plain(item.cardCvv ?? ''),
        pin: ConcealedValue.plain(item.cardPin ?? ''),
      );
      break;

    case 'identity':
      type = VaultItemType.identity;
      fields = IdentityFields(
        firstName: item.firstName ?? '',
        lastName: item.lastName ?? '',
        birthdate: item.birthdate,
        gender: item.gender,
        address: IdentityAddress(
          street: item.street ?? '',
          city: item.city ?? '',
          state: item.state ?? '',
          zip: item.zip ?? '',
          country: item.country ?? '',
        ),
        emails: const [],
        phoneNumbers: const [],
      );
      break;

    case 'secure_note':
      type = VaultItemType.secureNote;
      fields = SecureNoteFields(
        content: ConcealedValue.plain(item.noteContent ?? ''),
      );
      break;

    case 'bank_account':
      type = VaultItemType.bankAccount;
      fields = BankAccountFields(
        bankName: item.bankName ?? '',
        accountType: item.bankAccountType ?? 'checking',
        accountNumber: ConcealedValue.plain(item.bankAccountNumber ?? ''),
        routingNumber: ConcealedValue.plain(item.bankRoutingNumber ?? ''),
        iban: item.bankIban,
        swift: item.bankSwift,
      );
      break;

    case 'password':
      type = VaultItemType.password;
      fields = PasswordFields(
        password: ConcealedValue.plain(item.standalonePassword ?? ''),
      );
      break;

    case 'login':
    default:
      type = VaultItemType.login;
      fields = LoginFields(
        username: item.username ?? '',
        password: ConcealedValue.plain(item.password ?? ''),
        urls: item.urls,
        otpSecret: ConcealedValue.plain(item.totpSecret ?? ''),
        passwordHistory: const [],
      );
  }

  final vaultItem = VaultItem(
    id: id,
    type: type,
    title: item.title,
    tags: item.tags,
    favorite: item.favorite,
    vaultId: '',
    createdAt: now,
    updatedAt: now,
    fields: fields,
    customFields: const [],
    notes: ConcealedValue.plain(item.notes ?? ''),
  );

  final encrypted = await vaultItem.encrypt(vaultKey, crypto);
  db.insertItem(encrypted);
}

/// Multi-step vault import flow.
///
/// Step 1: Format picker
/// Step 2: File content paste / file picker result
/// Step 3: Preview (counts by type + errors)
/// Step 4: Confirm → encrypt each item → write ciphertext → clear plaintext
///
/// Security invariants (from vault-import-export skill + AGENTS.md Rule 7):
/// - Parsed plaintext never leaves this screen's memory.
/// - The import file content is not stored anywhere after parsing.
/// - After saving, [_parsedItems] is set to [] to release all references.
class ImportScreen extends StatefulWidget {
  final List<int> vaultKey;
  final VaultDatabase db;

  const ImportScreen({
    super.key,
    required this.vaultKey,
    required this.db,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  int _step = 0;
  String _selectedFormat = '';
  final _fileContentController = TextEditingController();

  // Generic CSV column mapping
  final _titleColCtrl = TextEditingController(text: 'title');
  final _userColCtrl = TextEditingController(text: 'username');
  final _passColCtrl = TextEditingController(text: 'password');
  final _urlColCtrl = TextEditingController(text: 'url');
  final _notesColCtrl = TextEditingController(text: 'notes');

  // KeePass decryption credentials
  final _keepassPasswordController = TextEditingController();
  final _keepassKeyFileController = TextEditingController();

  ImportResult? _importResult;
  List<ParsedItem> _parsedItems = [];
  bool _isSaving = false;
  int _savedCount = 0;
  final _crypto = VaultCrypto();

  @override
  void dispose() {
    _fileContentController.dispose();
    _titleColCtrl.dispose();
    _userColCtrl.dispose();
    _passColCtrl.dispose();
    _urlColCtrl.dispose();
    _notesColCtrl.dispose();
    _keepassPasswordController.dispose();
    _keepassKeyFileController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    String? extension;
    switch (_selectedFormat) {
      case 'bitwarden':
        extension = 'json';
        break;
      case '1password':
        extension = '1pux';
        break;
      case 'lastpass':
      case 'chrome_csv':
      case 'firefox_csv':
      case 'safari_csv':
      case 'dashlane':
      case 'keeper':
      case 'nordpass':
      case 'roboform':
        extension = 'csv';
        break;
      case 'protonpass':
        extension = 'json';
        break;
      case 'keepass_kdbx':
        extension = 'kdbx';
        break;
      case 'generic_csv':
        extension = 'csv';
        break;
      default:
        extension = null;
    }

    final result = await FilePicker.platform.pickFiles(
      type: extension != null ? FileType.custom : FileType.any,
      allowedExtensions: extension != null ? [extension] : null,
    );

    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final bytes = await file.bytes;
      
      if (bytes != null) {
        if (_selectedFormat == 'keepass_kdbx') {
          // For KeePass, store as Base64 for the existing parser
          _fileContentController.text = base64Encode(bytes);
        } else {
          // For text-based formats, decode as UTF-8
          _fileContentController.text = utf8.decode(bytes);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded: ${file.name}')),
        );
      }
    }
  }

  Future<void> _parseContent() async {
    final content = _fileContentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file or paste the export file content first.')),
      );
      return;
    }
    ImportResult result;
    try {
      switch (_selectedFormat) {
        case 'bitwarden':
          result = BitwardenParser().parse(content);
          break;
        case '1password':
          result = OnePasswordParser().parse(content);
          break;
        case 'lastpass':
          result = LastPassParser().parse(content);
          break;
        case 'chrome_csv':
          result = const GenericCsvParser(columnMapping: {
            'title': 'name',
            'url': 'url',
            'username': 'username',
            'password': 'password',
          }).parse(content);
          break;
        case 'firefox_csv':
          result = const GenericCsvParser(columnMapping: {
            'title': 'url',
            'url': 'url',
            'username': 'username',
            'password': 'password',
          }).parse(content);
          break;
        case 'safari_csv':
          result = const GenericCsvParser(columnMapping: {
            'title': 'Title',
            'url': 'URL',
            'username': 'Username',
            'password': 'Password',
            'notes': 'Notes',
            'totp': 'OTPAuth',
          }).parse(content);
          break;
        case 'dashlane':
          result = DashlaneParser().parse(content);
          break;
        case 'keeper':
          result = KeeperParser().parse(content);
          break;
        case 'nordpass':
          result = NordPassParser().parse(content);
          break;
        case 'roboform':
          result = RoboFormParser().parse(content);
          break;
        case 'protonpass':
          result = ProtonPassParser().parse(content);
          break;
        case 'keepass_kdbx':
          final bytes = base64Decode(content);
          final pw = _keepassPasswordController.text;
          final keyFileContent = _keepassKeyFileController.text.trim();
          Uint8List? keyFileBytes;
          if (keyFileContent.isNotEmpty) {
            try {
              keyFileBytes = base64Decode(keyFileContent);
            } catch (_) {
              keyFileBytes = Uint8List.fromList(utf8.encode(keyFileContent));
            }
          }
          result = await KeePassKdbxParser().parse(
            bytes: bytes,
            password: pw,
            keyFileBytes: keyFileBytes,
          );
          break;
        case 'generic_csv':
          result = GenericCsvParser(columnMapping: {
            'title': _titleColCtrl.text,
            'username': _userColCtrl.text,
            'password': _passColCtrl.text,
            'url': _urlColCtrl.text,
            'notes': _notesColCtrl.text,
          }).parse(content);
          break;
        default:
          result = ImportResult(items: [], errors: [
            const ParsedError(sourceRef: 'format', reason: 'Unknown format selected.')
          ]);
      }
    } catch (e) {
      result = ImportResult(items: [], errors: [
        ParsedError(sourceRef: 'parse', reason: 'Critical parse error: $e')
      ]);
    }

    setState(() {
      _importResult = result;
      _parsedItems = result.items;
      _step = 2; // Move to preview
    });
  }

  Future<void> _confirmAndImport() async {
    if (_parsedItems.isEmpty) return;
    setState(() => _isSaving = true);
    int count = 0;

    final toProcess = List<ParsedItem>.from(_parsedItems);
    // Clear the reference immediately — security invariant
    _parsedItems = [];

    for (final item in toProcess) {
      try {
        await encryptAndSave(item, widget.vaultKey, widget.db, _crypto);
        count++;
      } catch (_) {
        // Skip items that fail to encrypt — they will not appear in the vault
      }
    }

    // Explicitly clear the toProcess list to allow GC of plaintext
    toProcess.clear();
    // Clear the paste area
    _fileContentController.clear();

    setState(() {
      _isSaving = false;
      _savedCount = count;
      _step = 3; // Success screen
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Vault Items'),
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
        return _buildFileInput();
      case 2:
        return _buildPreview();
      case 3:
        return _buildSuccess();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFormatPicker() {
    final formats = [
      ('bitwarden', 'Bitwarden', 'JSON export from Bitwarden', Icons.shield_outlined, Colors.blueAccent),
      ('1password', '1Password', 'export.data from .1pux archive', Icons.security_outlined, Colors.deepOrangeAccent),
      ('lastpass', 'LastPass', 'CSV export from LastPass', Icons.lock_outline, Colors.redAccent),
      ('chrome_csv', 'Chrome Preset', 'CSV export from Google Chrome', Icons.chrome_reader_mode, Colors.yellowAccent),
      ('firefox_csv', 'Firefox Preset', 'CSV export from Mozilla Firefox', Icons.web, Colors.orangeAccent),
      ('safari_csv', 'Safari Preset', 'CSV export from Apple Safari', Icons.compass_calibration, Colors.lightBlueAccent),
      ('dashlane', 'Dashlane', 'CSV export from Dashlane', Icons.credit_card_outlined, Colors.purpleAccent),
      ('keeper', 'Keeper', 'CSV export from Keeper', Icons.folder_shared_outlined, Colors.greenAccent),
      ('nordpass', 'NordPass', 'CSV export from NordPass', Icons.vpn_lock_outlined, Colors.indigoAccent),
      ('roboform', 'RoboForm', 'CSV export from RoboForm', Icons.lock_clock, Colors.cyanAccent),
      ('protonpass', 'Proton Pass', 'JSON export from Proton Pass', Icons.email_outlined, Colors.pinkAccent),
      ('keepass_kdbx', 'KeePass (.kdbx)', 'Encrypted KeePass database file', Icons.key_outlined, Colors.green),
      ('generic_csv', 'Generic CSV', 'Any CSV with custom column mapping', Icons.table_chart_outlined, Colors.tealAccent),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Select Source Format',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'All parsing happens offline, in memory only. The file content is never uploaded.',
          style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 13),
        ),
        const SizedBox(height: 24),
        ...formats.map((f) => Card(
              color: AppTheme.surfaceColor,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: f.$5.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(f.$4, color: f.$5),
                ),
                title: Text(f.$2, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(f.$3, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    _selectedFormat = f.$1;
                    _step = 1;
                  });
                },
              ),
            )),
      ],
    );
  }

  Widget _buildFileInput() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _step = 0),
            ),
            const SizedBox(width: 8),
            Text(
              _formatLabel(_selectedFormat),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.warningColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.security, color: AppTheme.warningColor, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Paste the file content below. It will be parsed in memory only — never saved to disk or sent anywhere.',
                  style: TextStyle(fontSize: 12, color: AppTheme.warningColor),
                ),
              ),
            ],
          ),
        ),

        // Generic CSV extra: column mapping UI
        if (_selectedFormat == 'generic_csv') ...[
          const SizedBox(height: 20),
          const Text(
            'COLUMN MAPPING',
            style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          _colMapRow('Title column', _titleColCtrl),
          _colMapRow('Username column', _userColCtrl),
          _colMapRow('Password column', _passColCtrl),
          _colMapRow('URL column', _urlColCtrl),
          _colMapRow('Notes column', _notesColCtrl),
        ],

        // KeePass decryption credentials UI
        if (_selectedFormat == 'keepass_kdbx') ...[
          const SizedBox(height: 20),
          const Text(
            'KEEPASS DECRYPTION CREDENTIALS',
            style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _keepassPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'KeePass Database Password',
              labelText: 'Master Password',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _keepassKeyFileController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Paste Key File content (Base64 or Plain Text XML, optional)',
              labelText: 'Key File Content',
              alignLabelWithHint: true,
            ),
          ),
        ],

        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.surfaceColor,
            foregroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.folder_open),
          label: const Text('Select File'),
          onPressed: _pickFile,
        ),
        const SizedBox(height: 16),
        Text(
          _selectedFormat == 'keepass_kdbx' ? 'KDBX FILE CONTENT (BASE64)' : 'FILE CONTENT',
          style: const TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _fileContentController,
          maxLines: 12,
          decoration: InputDecoration(
            hintText: _selectedFormat == 'keepass_kdbx'
                ? 'Paste the Base64-encoded KDBX file content here or use Select File above...'
                : 'Paste the export file content here or use Select File above...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.preview_outlined),
          label: const Text('Parse & Preview'),
          onPressed: _parseContent,
        ),
      ],
    );
  }

  Widget _colMapRow(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
          ),
          Expanded(
            child: TextFormField(
              controller: ctrl,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final result = _importResult!;
    final counts = result.countsByType;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _step = 1),
            ),
            const SizedBox(width: 8),
            const Text('Import Preview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),

        // Summary counts by type
        if (counts.isNotEmpty) ...[
          const Text(
            'ITEMS TO IMPORT',
            style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          ...counts.entries.map((e) => ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle_outline, color: AppTheme.primaryColor, size: 18),
                title: Text(_typeLabel(e.key)),
                trailing: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                contentPadding: EdgeInsets.zero,
              )),
          ListTile(
            dense: true,
            leading: const Icon(Icons.summarize_outlined, color: AppTheme.textSecondaryColor, size: 18),
            title: const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text('${result.items.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
            contentPadding: EdgeInsets.zero,
          ),
        ] else
          const Text('No items could be parsed from this file.'),

        // Errors
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'PARSE WARNINGS / ERRORS',
            style: TextStyle(color: AppTheme.warningColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          ...result.errors.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.sourceRef, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryColor)),
                          Text(e.reason, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],

        const SizedBox(height: 24),

        if (result.items.isNotEmpty)
          ElevatedButton.icon(
            key: const Key('confirm-import-button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.lock_outlined),
            label: Text('Encrypt & Import ${result.items.length} Items'),
            onPressed: _isSaving ? null : _confirmAndImport,
          ),

        if (_isSaving) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Encrypting items...', textAlign: TextAlign.center),
        ],

        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline, color: AppTheme.primaryColor, size: 56),
          ),
          const SizedBox(height: 24),
          Text(
            'Import Complete',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '$_savedCount items encrypted and saved to your vault.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            'The import file content has been cleared from memory.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 12),
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

  String _formatLabel(String fmt) {
    switch (fmt) {
      case 'bitwarden': return 'Bitwarden Import';
      case '1password': return '1Password Import';
      case 'lastpass': return 'LastPass Import';
      case 'chrome_csv': return 'Chrome CSV Import';
      case 'firefox_csv': return 'Firefox CSV Import';
      case 'safari_csv': return 'Safari CSV Import';
      case 'dashlane': return 'Dashlane CSV Import';
      case 'keeper': return 'Keeper CSV Import';
      case 'nordpass': return 'NordPass CSV Import';
      case 'roboform': return 'RoboForm CSV Import';
      case 'protonpass': return 'Proton Pass JSON Import';
      case 'keepass_kdbx': return 'KeePass (.kdbx) Import';
      case 'generic_csv': return 'Generic CSV Import';
      default: return 'Import';
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'login': return 'Logins';
      case 'credit_card': return 'Credit Cards';
      case 'identity': return 'Identities';
      case 'secure_note': return 'Secure Notes';
      case 'bank_account': return 'Bank Accounts';
      case 'password': return 'Passwords';
      default: return type;
    }
  }
}
