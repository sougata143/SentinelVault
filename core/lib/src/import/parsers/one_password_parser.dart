import 'dart:convert';
import '../import_result.dart';

/// Parses a 1Password `.1pux` export (specifically the `export.data` JSON
/// extracted from the archive) into [ImportResult].
///
/// A `.1pux` file is a ZIP archive. The app layer is responsible for
/// extracting the `export.data` file and passing its content as [jsonContent].
/// This parser operates on the string only — never on a file path.
///
/// Supported category UUIDs:
///   001 = Login, 002 = Credit Card, 003 = Secure Note,
///   004 = Identity, 005 = Password
class OnePasswordParser {
  static const _catLogin = '001';
  static const _catCreditCard = '002';
  static const _catSecureNote = '003';
  static const _catIdentity = '004';
  static const _catPassword = '005';

  ImportResult parse(String jsonContent) {
    final items = <ParsedItem>[];
    final errors = <ParsedError>[];

    late Map<String, dynamic> root;
    try {
      root = jsonDecode(jsonContent) as Map<String, dynamic>;
    } catch (e) {
      errors.add(const ParsedError(
        sourceRef: 'root',
        reason: 'Invalid JSON in export.data file.',
      ));
      return ImportResult(items: items, errors: errors);
    }

    final accounts = root['accounts'] as List<dynamic>? ?? [];
    for (final account in accounts) {
      final vaults = (account as Map<String, dynamic>)['vaults'] as List<dynamic>? ?? [];
      for (final vault in vaults) {
        final rawItems = (vault as Map<String, dynamic>)['items'] as List<dynamic>? ?? [];
        for (var i = 0; i < rawItems.length; i++) {
          final raw = rawItems[i] as Map<String, dynamic>;
          final overview = raw['overview'] as Map<String, dynamic>? ?? {};
          final srcRef = 'item[$i] "${overview['title'] ?? ''}"';
          try {
            final parsed = _parseItem(raw, overview, srcRef);
            if (parsed != null) {
              items.add(parsed);
            } else {
              errors.add(ParsedError(
                sourceRef: srcRef,
                reason: 'Unsupported category UUID: ${raw['categoryUuid']}',
              ));
            }
          } catch (e) {
            errors.add(ParsedError(sourceRef: srcRef, reason: 'Parse error: $e'));
          }
        }
      }
    }

    return ImportResult(items: items, errors: errors);
  }

  ParsedItem? _parseItem(
    Map<String, dynamic> raw,
    Map<String, dynamic> overview,
    String srcRef,
  ) {
    final categoryUuid = raw['categoryUuid'] as String? ?? '';
    final title = overview['title'] as String? ?? '';
    final urls = (overview['urls'] as List<dynamic>? ?? [])
        .map((u) => (u as Map<String, dynamic>)['url'] as String? ?? '')
        .where((u) => u.isNotEmpty)
        .toList();
    final fav = (raw['favIndex'] as int? ?? 0) > 0;
    final details = raw['details'] as Map<String, dynamic>? ?? {};
    final sections = details['sections'] as List<dynamic>? ?? [];
    final notes = details['notes'] as String?;

    // Helper to find a field value across sections by field id
    String? findField(String id) {
      for (final sec in sections) {
        final fields = (sec as Map<String, dynamic>)['fields'] as List<dynamic>? ?? [];
        for (final f in fields) {
          final fm = f as Map<String, dynamic>;
          if (fm['id'] == id || fm['title'] == id) {
            final v = fm['value'] as Map<String, dynamic>?;
            return v?['string'] as String? ?? v?['concealed'] as String?;
          }
        }
      }
      return null;
    }

    switch (categoryUuid) {
      case _catLogin:
        final loginFields = details['loginFields'] as List<dynamic>? ?? [];
        String? username;
        String? password;
        String? totp;
        for (final lf in loginFields) {
          final lfm = lf as Map<String, dynamic>;
          final designation = lfm['designation'] as String?;
          if (designation == 'username') username = lfm['value'] as String?;
          if (designation == 'password') password = lfm['value'] as String?;
        }
        totp = findField('TOTP') ?? findField('one-time password');
        return ParsedItem(
          title: title,
          type: 'login',
          username: username,
          password: password,
          urls: urls,
          totpSecret: totp,
          notes: notes,
          favorite: fav,
        );

      case _catCreditCard:
        return ParsedItem(
          title: title,
          type: 'credit_card',
          cardholderName: findField('cardholder'),
          cardNumber: findField('ccnum'),
          cardBrand: findField('type'),
          cardExpiryMonth: int.tryParse(findField('expiry_mm') ?? ''),
          cardExpiryYear: int.tryParse(findField('expiry_yy') ?? ''),
          cardCvv: findField('cvv'),
          cardPin: findField('pin'),
          notes: notes,
          favorite: fav,
        );

      case _catSecureNote:
        return ParsedItem(
          title: title,
          type: 'secure_note',
          noteContent: notes,
          favorite: fav,
        );

      case _catIdentity:
        return ParsedItem(
          title: title,
          type: 'identity',
          firstName: findField('firstname'),
          lastName: findField('lastname'),
          birthdate: findField('birthdate'),
          gender: findField('sex'),
          street: findField('address1'),
          city: findField('city'),
          state: findField('state'),
          zip: findField('zip'),
          country: findField('country'),
          notes: notes,
          favorite: fav,
        );

      case _catPassword:
        return ParsedItem(
          title: title,
          type: 'password',
          standalonePassword: findField('password'),
          notes: notes,
          favorite: fav,
        );

      default:
        return null;
    }
  }
}
