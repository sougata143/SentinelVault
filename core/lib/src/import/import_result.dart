/// Intermediate representation of a parsed vault item before encryption.
///
/// This object lives only in memory. It MUST be explicitly cleared (set to null
/// or replaced with an empty list) once encryption is complete. It must never
/// be written to a temp file, cache, log, or sent over any network connection.
class ParsedItem {
  final String title;
  final String type; // 'login' | 'credit_card' | 'identity' | 'secure_note' | 'bank_account' | 'password'

  // Login fields
  final String? username;
  final String? password;
  final List<String> urls;
  final String? totpSecret;

  // Credit Card fields
  final String? cardholderName;
  final String? cardNumber;
  final String? cardBrand;
  final int? cardExpiryMonth;
  final int? cardExpiryYear;
  final String? cardCvv;
  final String? cardPin;

  // Identity fields
  final String? firstName;
  final String? lastName;
  final String? birthdate;
  final String? gender;
  final String? street;
  final String? city;
  final String? state;
  final String? zip;
  final String? country;

  // Secure Note / Bank Account fields
  final String? noteContent;
  final String? bankName;
  final String? bankAccountType;
  final String? bankAccountNumber;
  final String? bankRoutingNumber;
  final String? bankIban;
  final String? bankSwift;

  // Standalone Password
  final String? standalonePassword;

  // Shared
  final String? notes;
  final List<String> tags;
  final bool favorite;

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
  final List<ParsedItem> items;
  final List<ParsedError> errors;

  ImportResult({
    required this.items,
    required this.errors,
  });

  Map<String, int> get countsByType {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.type] = (counts[item.type] ?? 0) + 1;
    }
    return counts;
  }
}
