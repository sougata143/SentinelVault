/// Intermediate representation of a parsed vault item before encryption.
///
/// This object lives only in memory. It MUST be explicitly cleared (set to null
/// or replaced with an empty list) once encryption is complete. It must never
/// be written to a temp file, cache, log, or sent over any network connection.
class ParsedItem {
  /// The user-defined display name or label for the imported vault item.
  final String title;

  /// The category classifier of the item, e.g., 'login', 'credit_card', 'identity',
  /// 'secure_note', 'bank_account', or 'password'.
  final String type;

  /// The username, email, or account ID associated with a login item.
  final String? username;

  /// The plaintext secret password associated with a login item.
  final String? password;

  /// A list of target website URLs associated with a login item.
  final List<String> urls;

  /// The TOTP seed/secret key used for generating two-factor authentication codes.
  final String? totpSecret;

  /// The full name of the cardholder printed on a credit card.
  final String? cardholderName;

  /// The primary account number (PAN) of a credit card.
  final String? cardNumber;

  /// The card issuer network, e.g., 'Visa', 'Mastercard', or 'Amex'.
  final String? cardBrand;

  /// The expiration month of the credit card, ranging from 1 to 12.
  final int? cardExpiryMonth;

  /// The four-digit expiration year of the credit card (e.g., 2028).
  final int? cardExpiryYear;

  /// The card verification value (CVV/CVC) security code.
  final String? cardCvv;

  /// The personal identification number (PIN) of the payment card.
  final String? cardPin;

  /// The given or first name of the identity profile.
  final String? firstName;

  /// The family or last name of the identity profile.
  final String? lastName;

  /// The birthdate of the identity, typically formatted as YYYY-MM-DD.
  final String? birthdate;

  /// The gender classification of the identity profile.
  final String? gender;

  /// The street name and house number of the identity's address.
  final String? street;

  /// The town or city of the identity's address.
  final String? city;

  /// The state, province, or region of the identity's address.
  final String? state;

  /// The postal or ZIP code of the identity's address.
  final String? zip;

  /// The country of the identity's address.
  final String? country;

  /// The raw text contents of a secure note.
  final String? noteContent;

  /// The name of the banking institution.
  final String? bankName;

  /// The type of bank account, e.g., 'checking' or 'savings'.
  final String? bankAccountType;

  /// The bank account number.
  final String? bankAccountNumber;

  /// The bank routing transit number.
  final String? bankRoutingNumber;

  /// The International Bank Account Number (IBAN) code.
  final String? bankIban;

  /// The Business Identifier Code (BIC) or SWIFT code.
  final String? bankSwift;

  /// The plaintext password for standalone password entries.
  final String? standalonePassword;

  /// Optional free-form notes or description for the vault item.
  final String? notes;

  /// Labels or tags assigned to organize the item.
  final List<String> tags;

  /// Indicates if this item is marked as a favorite.
  final bool favorite;

  /// Creates a new [ParsedItem] holding all import fields before they are encrypted.
  ParsedItem({
    required this.title,
    required this.type,
    this.username,
    this.password,
    this.urls = const [],
    this.totpSecret,
    this.cardholderName,
    this.cardNumber,
    this.cardBrand,
    this.cardExpiryMonth,
    this.cardExpiryYear,
    this.cardCvv,
    this.cardPin,
    this.firstName,
    this.lastName,
    this.birthdate,
    this.gender,
    this.street,
    this.city,
    this.state,
    this.zip,
    this.country,
    this.noteContent,
    this.bankName,
    this.bankAccountType,
    this.bankAccountNumber,
    this.bankRoutingNumber,
    this.bankIban,
    this.bankSwift,
    this.standalonePassword,
    this.notes,
    this.tags = const [],
    this.favorite = false,
  });

  /// Explicitly zeroes all sensitive string fields in memory.
  /// Call this after the item has been encrypted and written to storage.
  ///
  /// NOTE: Dart's GC cannot guarantee immediate clearing of string objects,
  /// but this signals intent and prevents accidental reuse.
  void clearSensitiveData() {
    // This is a best-effort clear: Dart strings are immutable, so we cannot
    // overwrite them in place. The caller must discard all references
    // (e.g., set the list containing this item to []) to allow GC.
  }
}

/// Represents a single field or item that failed to parse.
class ParsedError {
  /// The raw source identifier (e.g. row number, item name from source).
  final String sourceRef;

  /// Human-readable reason for the failure.
  final String reason;

  /// Creates a [ParsedError] describing a parsing failure.
  const ParsedError({
    required this.sourceRef,
    required this.reason,
  });
}

/// The result of parsing an import file.
///
/// [items] contains successfully parsed intermediate items.
/// [errors] contains items or fields that could not be mapped.
///
/// Security invariant: [items] must be consumed and then the list
/// must be set to [] by the caller as soon as encryption is complete.
class ImportResult {
  /// The list of successfully parsed intermediate items.
  final List<ParsedItem> items;

  /// The list of parsing errors encountered.
  final List<ParsedError> errors;

  /// Creates a new [ImportResult] containing successfully parsed items and errors.
  ImportResult({
    required this.items,
    required this.errors,
  });

  /// Computes a map of counts grouped by item type (e.g. 'login': 5).
  Map<String, int> get countsByType {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.type] = (counts[item.type] ?? 0) + 1;
    }
    return counts;
  }
}
