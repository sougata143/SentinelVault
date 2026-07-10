import 'dart:convert';
import '../crypto/crypto.dart';
import 'models.dart';

/// Enum representing the supported vault item types.
enum VaultItemType {
  login,
  creditCard,
  identity,
  secureNote,
  bankAccount,
  password,
}

extension VaultItemTypeExtension on VaultItemType {
  String toValue() {
    switch (this) {
      case VaultItemType.login:
        return 'login';
      case VaultItemType.creditCard:
        return 'credit_card';
      case VaultItemType.identity:
        return 'identity';
      case VaultItemType.secureNote:
        return 'secure_note';
      case VaultItemType.bankAccount:
        return 'bank_account';
      case VaultItemType.password:
        return 'password';
    }
  }

  static VaultItemType fromValue(String value) {
    switch (value) {
      case 'login':
        return VaultItemType.login;
      case 'credit_card':
        return VaultItemType.creditCard;
      case 'identity':
        return VaultItemType.identity;
      case 'secure_note':
        return VaultItemType.secureNote;
      case 'bank_account':
        return VaultItemType.bankAccount;
      case 'password':
        return VaultItemType.password;
      default:
        throw ArgumentError('Invalid VaultItemType value: $value');
    }
  }
}

/// Represents a value that can be concealed (encrypted individually).
class ConcealedValue {
  final String? plaintext;
  final String? ciphertext;
  final String? nonce;

  bool get isEncrypted => ciphertext != null && nonce != null;

  const ConcealedValue.plain(this.plaintext)
      : ciphertext = null,
        nonce = null;

  const ConcealedValue.encrypted({required this.ciphertext, required this.nonce})
      : plaintext = null;

  /// Encrypts the plaintext value using [VaultCrypto].
  Future<ConcealedValue> encrypt(List<int> key, VaultCrypto crypto) async {
    if (isEncrypted) return this;
    if (plaintext == null || plaintext!.isEmpty) {
      return const ConcealedValue.plain('');
    }

    final nonceBytes = crypto.generateRandomBytes(12);
    final encryptedBytes = await crypto.encryptAesGcm(
      plaintext: utf8.encode(plaintext!),
      key: key,
      nonce: nonceBytes,
    );

    return ConcealedValue.encrypted(
      ciphertext: base64.encode(encryptedBytes),
      nonce: base64.encode(nonceBytes),
    );
  }

  /// Decrypts the ciphertext value using [VaultCrypto].
  Future<ConcealedValue> decrypt(List<int> key, VaultCrypto crypto) async {
    if (!isEncrypted) return this;
    if (ciphertext == null || nonce == null) {
      return const ConcealedValue.plain('');
    }

    try {
      final decryptedBytes = await crypto.decryptAesGcm(
        ciphertextAndMac: base64.decode(ciphertext!),
        key: key,
        nonce: base64.decode(nonce!),
      );
      return ConcealedValue.plain(utf8.decode(decryptedBytes));
    } catch (_) {
      // Return empty if decryption fails
      return const ConcealedValue.plain('');
    }
  }

  Map<String, dynamic> toJson() {
    if (isEncrypted) {
      return {
        'ciphertext': ciphertext,
        'nonce': nonce,
      };
    }
    return {
      'plaintext': plaintext,
    };
  }

  factory ConcealedValue.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('ciphertext') && json.containsKey('nonce')) {
      return ConcealedValue.encrypted(
        ciphertext: json['ciphertext'] as String,
        nonce: json['nonce'] as String,
      );
    }
    return ConcealedValue.plain(json['plaintext'] as String? ?? '');
  }
}

/// Base class for type-specific vault item fields.
abstract class VaultItemFields {
  Map<String, dynamic> toJson();
  Future<VaultItemFields> encrypt(List<int> key, VaultCrypto crypto);
  Future<VaultItemFields> decrypt(List<int> key, VaultCrypto crypto);
}

// ── Login Fields ──────────────────────────────────────────────────────────

class PasswordHistoryEntry {
  final ConcealedValue password;
  final DateTime changedAt;

  PasswordHistoryEntry({required this.password, required this.changedAt});

  Map<String, dynamic> toJson() => {
        'password': password.toJson(),
        'changed_at': changedAt.toIso8601String(),
      };

  factory PasswordHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PasswordHistoryEntry(
      password: ConcealedValue.fromJson(json['password'] as Map<String, dynamic>),
      changedAt: DateTime.parse(json['changed_at'] as String),
    );
  }
}

class LoginFields implements VaultItemFields {
  final String username;
  final ConcealedValue password;
  final List<String> urls;
  final ConcealedValue otpSecret;
  final List<PasswordHistoryEntry> passwordHistory;

  LoginFields({
    required this.username,
    required this.password,
    required this.urls,
    required this.otpSecret,
    required this.passwordHistory,
  });

  @override
  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password.toJson(),
        'urls': urls,
        'otp_secret': otpSecret.toJson(),
        'password_history': passwordHistory.map((e) => e.toJson()).toList(),
      };

  factory LoginFields.fromJson(Map<String, dynamic> json) {
    return LoginFields(
      username: json['username'] as String? ?? '',
      password: json['password'] != null
          ? ConcealedValue.fromJson(json['password'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
      urls: List<String>.from(json['urls'] as List? ?? []),
      otpSecret: json['otp_secret'] != null
          ? ConcealedValue.fromJson(json['otp_secret'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
      passwordHistory: (json['password_history'] as List? ?? [])
          .map((e) => PasswordHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<LoginFields> encrypt(List<int> key, VaultCrypto crypto) async {
    final encPassword = await password.encrypt(key, crypto);
    final encOtp = await otpSecret.encrypt(key, crypto);
    final encHistory = await Future.wait(
      passwordHistory.map((e) async => PasswordHistoryEntry(
            password: await e.password.encrypt(key, crypto),
            changedAt: e.changedAt,
          )),
    );
    return LoginFields(
      username: username,
      password: encPassword,
      urls: urls,
      otpSecret: encOtp,
      passwordHistory: encHistory,
    );
  }

  @override
  Future<LoginFields> decrypt(List<int> key, VaultCrypto crypto) async {
    final decPassword = await password.decrypt(key, crypto);
    final decOtp = await otpSecret.decrypt(key, crypto);
    final decHistory = await Future.wait(
      passwordHistory.map((e) async => PasswordHistoryEntry(
            password: await e.password.decrypt(key, crypto),
            changedAt: e.changedAt,
          )),
    );
    return LoginFields(
      username: username,
      password: decPassword,
      urls: urls,
      otpSecret: decOtp,
      passwordHistory: decHistory,
    );
  }
}

// ── Credit Card Fields ────────────────────────────────────────────────────

class CreditCardFields implements VaultItemFields {
  final String cardholderName;
  final ConcealedValue cardNumber;
  final String brand;
  final int expiryMonth;
  final int expiryYear;
  final ConcealedValue cvv;
  final ConcealedValue pin;
  final String? billingAddressRef;

  CreditCardFields({
    required this.cardholderName,
    required this.cardNumber,
    required this.brand,
    required this.expiryMonth,
    required this.expiryYear,
    required this.cvv,
    required this.pin,
    this.billingAddressRef,
  });

  @override
  Map<String, dynamic> toJson() => {
        'cardholder_name': cardholderName,
        'card_number': cardNumber.toJson(),
        'brand': brand,
        'expiry_month': expiryMonth,
        'expiry_year': expiryYear,
        'cvv': cvv.toJson(),
        'pin': pin.toJson(),
        'billing_address_ref': billingAddressRef,
      };

  factory CreditCardFields.fromJson(Map<String, dynamic> json) {
    return CreditCardFields(
      cardholderName: json['cardholder_name'] as String? ?? '',
      cardNumber: json['card_number'] != null
          ? ConcealedValue.fromJson(json['card_number'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
      brand: json['brand'] as String? ?? 'other',
      expiryMonth: json['expiry_month'] as int? ?? 1,
      expiryYear: json['expiry_year'] as int? ?? 2026,
      cvv: json['cvv'] != null
          ? ConcealedValue.fromJson(json['cvv'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
      pin: json['pin'] != null
          ? ConcealedValue.fromJson(json['pin'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
      billingAddressRef: json['billing_address_ref'] as String?,
    );
  }

  @override
  Future<CreditCardFields> encrypt(List<int> key, VaultCrypto crypto) async {
    return CreditCardFields(
      cardholderName: cardholderName,
      cardNumber: await cardNumber.encrypt(key, crypto),
      brand: brand,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cvv: await cvv.encrypt(key, crypto),
      pin: await pin.encrypt(key, crypto),
      billingAddressRef: billingAddressRef,
    );
  }

  @override
  Future<CreditCardFields> decrypt(List<int> key, VaultCrypto crypto) async {
    return CreditCardFields(
      cardholderName: cardholderName,
      cardNumber: await cardNumber.decrypt(key, crypto),
      brand: brand,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cvv: await cvv.decrypt(key, crypto),
      pin: await pin.decrypt(key, crypto),
      billingAddressRef: billingAddressRef,
    );
  }
}

// ── Identity Fields ───────────────────────────────────────────────────────

class IdentityAddress {
  final String street;
  final String city;
  final String state;
  final String zip;
  final String country;

  IdentityAddress({
    required this.street,
    required this.city,
    required this.state,
    required this.zip,
    required this.country,
  });

  Map<String, dynamic> toJson() => {
        'street': street,
        'city': city,
        'state': state,
        'zip': zip,
        'country': country,
      };

  factory IdentityAddress.fromJson(Map<String, dynamic> json) {
    return IdentityAddress(
      street: json['street'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zip: json['zip'] as String? ?? '',
      country: json['country'] as String? ?? '',
    );
  }
}

class IdentityFields implements VaultItemFields {
  final String firstName;
  final String lastName;
  final String? birthdate;
  final String? gender;
  final IdentityAddress address;
  final List<String> emails;
  final List<String> phoneNumbers;
  final String? company;
  final String? jobTitle;
  final String? website;

  IdentityFields({
    required this.firstName,
    required this.lastName,
    this.birthdate,
    this.gender,
    required this.address,
    required this.emails,
    required this.phoneNumbers,
    this.company,
    this.jobTitle,
    this.website,
  });

  @override
  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'birthdate': birthdate,
        'gender': gender,
        'address': address.toJson(),
        'emails': emails,
        'phone_numbers': phoneNumbers,
        'company': company,
        'job_title': jobTitle,
        'website': website,
      };

  factory IdentityFields.fromJson(Map<String, dynamic> json) {
    return IdentityFields(
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      birthdate: json['birthdate'] as String?,
      gender: json['gender'] as String?,
      address: json['address'] != null
          ? IdentityAddress.fromJson(json['address'] as Map<String, dynamic>)
          : IdentityAddress(street: '', city: '', state: '', zip: '', country: ''),
      emails: List<String>.from(json['emails'] as List? ?? []),
      phoneNumbers: List<String>.from(json['phone_numbers'] as List? ?? []),
      company: json['company'] as String?,
      jobTitle: json['job_title'] as String?,
      website: json['website'] as String?,
    );
  }

  @override
  Future<IdentityFields> encrypt(List<int> key, VaultCrypto crypto) async => this;

  @override
  Future<IdentityFields> decrypt(List<int> key, VaultCrypto crypto) async => this;
}

// ── Secure Note Fields ────────────────────────────────────────────────────

class SecureNoteFields implements VaultItemFields {
  final ConcealedValue content;

  SecureNoteFields({required this.content});

  @override
  Map<String, dynamic> toJson() => {
        'content': content.toJson(),
      };

  factory SecureNoteFields.fromJson(Map<String, dynamic> json) {
    return SecureNoteFields(
      content: json['content'] != null
          ? ConcealedValue.fromJson(json['content'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
    );
  }

  @override
  Future<SecureNoteFields> encrypt(List<int> key, VaultCrypto crypto) async {
    return SecureNoteFields(content: await content.encrypt(key, crypto));
  }

  @override
  Future<SecureNoteFields> decrypt(List<int> key, VaultCrypto crypto) async {
    return SecureNoteFields(content: await content.decrypt(key, crypto));
  }
}

// ── Bank Account Fields ───────────────────────────────────────────────────

class BankAccountFields implements VaultItemFields {
  final String bankName;
  final String accountType; // checking | savings | other
  final ConcealedValue accountNumber;
  final ConcealedValue routingNumber;
  final String? iban;
  final String? swift;

  BankAccountFields({
    required this.bankName,
    required this.accountType,
    required this.accountNumber,
    required this.routingNumber,
    this.iban,
    this.swift,
  });

  @override
  Map<String, dynamic> toJson() => {
        'bank_name': bankName,
        'account_type': accountType,
        'account_number': accountNumber.toJson(),
        'routing_number': routingNumber.toJson(),
        'iban': iban,
        'swift': swift,
      };

  factory BankAccountFields.fromJson(Map<String, dynamic> json) {
    return BankAccountFields(
      bankName: json['bank_name'] as String? ?? '',
      accountType: json['account_type'] as String? ?? 'other',
      accountNumber: json['account_number'] != null
          ? ConcealedValue.fromJson(json['account_number'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
      routingNumber: json['routing_number'] != null
          ? ConcealedValue.fromJson(json['routing_number'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
      iban: json['iban'] as String?,
      swift: json['swift'] as String?,
    );
  }

  @override
  Future<BankAccountFields> encrypt(List<int> key, VaultCrypto crypto) async {
    return BankAccountFields(
      bankName: bankName,
      accountType: accountType,
      accountNumber: await accountNumber.encrypt(key, crypto),
      routingNumber: await routingNumber.encrypt(key, crypto),
      iban: iban,
      swift: swift,
    );
  }

  @override
  Future<BankAccountFields> decrypt(List<int> key, VaultCrypto crypto) async {
    return BankAccountFields(
      bankName: bankName,
      accountType: accountType,
      accountNumber: await accountNumber.decrypt(key, crypto),
      routingNumber: await routingNumber.decrypt(key, crypto),
      iban: iban,
      swift: swift,
    );
  }
}

// ── Standalone Password Fields ────────────────────────────────────────────

class PasswordFields implements VaultItemFields {
  final ConcealedValue password;

  PasswordFields({required this.password});

  @override
  Map<String, dynamic> toJson() => {
        'password': password.toJson(),
      };

  factory PasswordFields.fromJson(Map<String, dynamic> json) {
    return PasswordFields(
      password: json['password'] != null
          ? ConcealedValue.fromJson(json['password'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
    );
  }

  @override
  Future<PasswordFields> encrypt(List<int> key, VaultCrypto crypto) async {
    return PasswordFields(password: await password.encrypt(key, crypto));
  }

  @override
  Future<PasswordFields> decrypt(List<int> key, VaultCrypto crypto) async {
    return PasswordFields(password: await password.decrypt(key, crypto));
  }
}

// ── Custom Field ──────────────────────────────────────────────────────────

class CustomField {
  final String label;
  final String type; // text | concealed | url | date | otp
  final ConcealedValue value;

  CustomField({
    required this.label,
    required this.type,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'type': type,
        'value': value.toJson(),
      };

  factory CustomField.fromJson(Map<String, dynamic> json) {
    return CustomField(
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      value: json['value'] != null
          ? ConcealedValue.fromJson(json['value'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
    );
  }

  Future<CustomField> encrypt(List<int> key, VaultCrypto crypto) async {
    if (type == 'concealed') {
      return CustomField(label: label, type: type, value: await value.encrypt(key, crypto));
    }
    return this;
  }

  Future<CustomField> decrypt(List<int> key, VaultCrypto crypto) async {
    if (type == 'concealed') {
      return CustomField(label: label, type: type, value: await value.decrypt(key, crypto));
    }
    return this;
  }
}

// ── Shared VaultItem Envelope ─────────────────────────────────────────────

class VaultItem {
  final String id;
  final VaultItemType type;
  final String title;
  final List<String> tags;
  final bool favorite;
  final String vaultId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final VaultItemFields fields;
  final List<CustomField> customFields;
  final ConcealedValue notes;

  VaultItem({
    required this.id,
    required this.type,
    required this.title,
    required this.tags,
    required this.favorite,
    required this.vaultId,
    required this.createdAt,
    required this.updatedAt,
    required this.fields,
    required this.customFields,
    required this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.toValue(),
        'title': title,
        'tags': tags,
        'favorite': favorite,
        'vault_id': vaultId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'fields': fields.toJson(),
        'custom_fields': customFields.map((e) => e.toJson()).toList(),
        'notes': notes.toJson(),
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    final type = VaultItemTypeExtension.fromValue(json['type'] as String);
    final fieldsJson = json['fields'] as Map<String, dynamic>? ?? {};

    VaultItemFields fields;
    switch (type) {
      case VaultItemType.login:
        fields = LoginFields.fromJson(fieldsJson);
        break;
      case VaultItemType.creditCard:
        fields = CreditCardFields.fromJson(fieldsJson);
        break;
      case VaultItemType.identity:
        fields = IdentityFields.fromJson(fieldsJson);
        break;
      case VaultItemType.secureNote:
        fields = SecureNoteFields.fromJson(fieldsJson);
        break;
      case VaultItemType.bankAccount:
        fields = BankAccountFields.fromJson(fieldsJson);
        break;
      case VaultItemType.password:
        fields = PasswordFields.fromJson(fieldsJson);
        break;
    }

    return VaultItem(
      id: json['id'] as String,
      type: type,
      title: json['title'] as String? ?? '',
      tags: List<String>.from(json['tags'] as List? ?? []),
      favorite: json['favorite'] as bool? ?? false,
      vaultId: json['vault_id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      fields: fields,
      customFields: (json['custom_fields'] as List? ?? [])
          .map((e) => CustomField.fromJson(e as Map<String, dynamic>))
          .toList(),
      notes: json['notes'] != null
          ? ConcealedValue.fromJson(json['notes'] as Map<String, dynamic>)
          : const ConcealedValue.plain(''),
    );
  }

  /// Encrypts the [VaultItem] into an [EncryptedVaultItem] under [vaultKey].
  Future<EncryptedVaultItem> encrypt(List<int> vaultKey, VaultCrypto crypto) async {
    // 1. Encrypt inner fields
    final encryptedFields = await fields.encrypt(vaultKey, crypto);

    // 2. Encrypt inner custom fields
    final encryptedCustomFields = await Future.wait(
      customFields.map((f) => f.encrypt(vaultKey, crypto)),
    );

    // 3. Encrypt notes
    final encryptedNotes = await notes.encrypt(vaultKey, crypto);

    // 4. Create encrypted envelope object
    final innerEnvelope = VaultItem(
      id: id,
      type: type,
      title: title,
      tags: tags,
      favorite: favorite,
      vaultId: vaultId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      fields: encryptedFields,
      customFields: encryptedCustomFields,
      notes: encryptedNotes,
    );

    // 5. Serialize outer envelope and encrypt as a single blob
    final envelopeJson = jsonEncode(innerEnvelope.toJson());
    final envelopeBytes = utf8.encode(envelopeJson);
    final outerNonce = crypto.generateRandomBytes(12);

    final outerCiphertextBytes = await crypto.encryptAesGcm(
      plaintext: envelopeBytes,
      key: vaultKey,
      nonce: outerNonce,
    );

    return EncryptedVaultItem(
      id: id,
      encryptedBlob: base64.encode(outerCiphertextBytes),
      nonce: base64.encode(outerNonce),
      version: 1,
      updatedAt: updatedAt,
    );
  }

  /// Decrypts [EncryptedVaultItem] to get the plaintext [VaultItem].
  /// Supports Phase 4 legacy migration: if the encryptedBlob starts with
  /// 'encrypted:', it parses it directly without AES decryption.
  static Future<VaultItem> decrypt(
    EncryptedVaultItem encryptedItem,
    List<int> vaultKey,
    VaultCrypto crypto,
  ) async {
    // ── Phase 4 Migration Detection ───────────────────────────────────────
    if (encryptedItem.encryptedBlob.startsWith('encrypted:')) {
      final parts = encryptedItem.encryptedBlob.split(':');
      String title = 'Vault Item';
      String username = '';
      String passwordValue = '';

      if (parts.length >= 4) {
        title = parts[1];
        username = parts[2];
        passwordValue = parts[3];
      }

      // Convert legacy items directly into type: "login" under the new schema
      return VaultItem(
        id: encryptedItem.id,
        type: VaultItemType.login,
        title: title,
        tags: const [],
        favorite: false,
        vaultId: '',
        createdAt: encryptedItem.updatedAt,
        updatedAt: encryptedItem.updatedAt,
        fields: LoginFields(
          username: username,
          password: ConcealedValue.plain(passwordValue),
          urls: const [],
          otpSecret: const ConcealedValue.plain(''),
          passwordHistory: const [],
        ),
        customFields: const [],
        notes: const ConcealedValue.plain(''),
      );
    }

    // ── Standard Decryption ───────────────────────────────────────────────
    final outerCiphertextBytes = base64.decode(encryptedItem.encryptedBlob);
    final outerNonceBytes = base64.decode(encryptedItem.nonce);

    final decryptedBytes = await crypto.decryptAesGcm(
      ciphertextAndMac: outerCiphertextBytes,
      key: vaultKey,
      nonce: outerNonceBytes,
    );

    final envelopeJson = utf8.decode(decryptedBytes);
    final envelopeMap = jsonDecode(envelopeJson) as Map<String, dynamic>;
    final item = VaultItem.fromJson(envelopeMap);

    // Decrypt all inner secret fields and custom fields
    final decryptedFields = await item.fields.decrypt(vaultKey, crypto);
    final decryptedCustomFields = await Future.wait(
      item.customFields.map((f) => f.decrypt(vaultKey, crypto)),
    );
    final decryptedNotes = await item.notes.decrypt(vaultKey, crypto);

    return VaultItem(
      id: item.id,
      type: item.type,
      title: item.title,
      tags: item.tags,
      favorite: item.favorite,
      vaultId: item.vaultId,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      fields: decryptedFields,
      customFields: decryptedCustomFields,
      notes: decryptedNotes,
    );
  }
}
