import 'dart:convert';
import '../import_result.dart';

/// Parses a Bitwarden JSON export into [ImportResult].
///
/// Accepts the raw JSON string. The file is never saved to disk — parsing
/// happens entirely in memory. The caller must discard the string reference
/// after calling [parse].
///
/// Bitwarden export format: `{ "encrypted": false, "items": [...] }`
/// Item types: 1 = Login, 2 = SecureNote, 3 = Card, 4 = Identity
class BitwardenParser {
  static const _typeLogin = 1;
  static const _typeSecureNote = 2;
  static const _typeCard = 3;
  static const _typeIdentity = 4;

  /// Parses [jsonContent] and returns an [ImportResult].
  ///
  /// Any item that cannot be mapped to a known type or is missing required
  /// fields is added to [ImportResult.errors] — never silently dropped.
  ImportResult parse(String jsonContent) {
    final items = <ParsedItem>[];
    final errors = <ParsedError>[];

    late Map<String, dynamic> root;
    try {
      root = jsonDecode(jsonContent) as Map<String, dynamic>;
    } catch (e) {
      errors.add(const ParsedError(
        sourceRef: 'root',
        reason: 'Invalid JSON: could not parse the export file.',
      ));
      return ImportResult(items: items, errors: errors);
    }

    if (root['encrypted'] == true) {
      errors.add(const ParsedError(
        sourceRef: 'root',
        reason: 'This export is encrypted. Export without encryption from Bitwarden before importing.',
      ));
      return ImportResult(items: items, errors: errors);
    }

    final rawItems = root['items'] as List<dynamic>? ?? [];

    for (var i = 0; i < rawItems.length; i++) {
      final raw = rawItems[i] as Map<String, dynamic>;
      final srcRef = 'item[$i] "${raw['name'] ?? ''}"';

      try {
        final parsed = _parseItem(raw, srcRef);
        if (parsed != null) {
          items.add(parsed);
        }
      } catch (e) {
        errors.add(ParsedError(
          sourceRef: srcRef,
          reason: 'Unexpected parse error: $e',
        ));
      }
    }

    return ImportResult(items: items, errors: errors);
  }

  ParsedItem? _parseItem(Map<String, dynamic> raw, String srcRef) {
    final type = raw['type'] as int?;
    final name = raw['name'] as String? ?? '';
    final notes = raw['notes'] as String?;
    final fav = raw['favorite'] as bool? ?? false;

    final tags = <String>[];

    // Bitwarden doesn't have native tags in the base export schema,
    // but some versions include `collectionIds`. We skip those for now.

    switch (type) {
      case _typeLogin:
        final login = raw['login'] as Map<String, dynamic>? ?? {};
        final uriObjects = login['uris'] as List<dynamic>? ?? [];
        final urls = uriObjects
            .map((u) => (u as Map<String, dynamic>)['uri'] as String? ?? '')
            .where((u) => u.isNotEmpty)
            .toList();
        return ParsedItem(
          title: name,
          type: 'login',
          username: login['username'] as String?,
          password: login['password'] as String?,
          urls: urls,
          totpSecret: login['totp'] as String?,
          notes: notes,
          tags: tags,
          favorite: fav,
        );

      case _typeSecureNote:
        return ParsedItem(
          title: name,
          type: 'secure_note',
          noteContent: notes,
          notes: null,
          tags: tags,
          favorite: fav,
        );

      case _typeCard:
        final card = raw['card'] as Map<String, dynamic>? ?? {};
        final expMonth = int.tryParse(card['expMonth']?.toString() ?? '');
        final expYear = int.tryParse(card['expYear']?.toString() ?? '');
        return ParsedItem(
          title: name,
          type: 'credit_card',
          cardholderName: card['cardholderName'] as String?,
          cardNumber: card['number'] as String?,
          cardBrand: card['brand'] as String?,
          cardExpiryMonth: expMonth,
          cardExpiryYear: expYear,
          cardCvv: card['code'] as String?,
          notes: notes,
          tags: tags,
          favorite: fav,
        );

      case _typeIdentity:
        final id = raw['identity'] as Map<String, dynamic>? ?? {};
        return ParsedItem(
          title: name,
          type: 'identity',
          firstName: id['firstName'] as String?,
          lastName: id['lastName'] as String?,
          birthdate: null,
          street: id['address1'] as String?,
          city: id['city'] as String?,
          state: id['state'] as String?,
          zip: id['postalCode'] as String?,
          country: id['country'] as String?,
          notes: notes,
          tags: tags,
          favorite: fav,
        );

      default:
        throw ArgumentError('Unknown item type: $type');
    }
  }
}
