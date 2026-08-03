import 'dart:convert';
import '../import_result.dart';

/// Parses a 1Password `.1pux` export (specifically the `export.data` JSON
/// extracted from the archive) into [ImportResult].
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

  /// Parses 1Password JSON export content [jsonContent] into parsed items and errors.
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
    final topFields = details['fields'] as List<dynamic>? ?? [];
    final notes = (details['notesPlain'] as String?) ?? (details['notes'] as String?);

    List<Map<String, dynamic>> getAllFields() {
      final all = <Map<String, dynamic>>[];
      for (final f in topFields) {
        if (f is Map<String, dynamic>) all.add(f);
      }
      for (final sec in sections) {
        final fields = (sec as Map<String, dynamic>)['fields'] as List<dynamic>? ?? [];
        for (final f in fields) {
          if (f is Map<String, dynamic>) all.add(f);
        }
      }
      return all;
    }

    final allFields = getAllFields();

    String? findField(String idOrTitle) {
      final target = idOrTitle.toLowerCase();
      for (final fm in allFields) {
        final fid = (fm['id'] as String? ?? '').toLowerCase();
        final ftitle = (fm['title'] as String? ?? '').toLowerCase();
        final flabel = (fm['label'] as String? ?? '').toLowerCase();

        if (fid == target || ftitle == target || flabel == target) {
          final v = fm['value'];
          if (v is Map<String, dynamic>) {
            return v['string'] as String? ?? v['concealed'] as String? ?? v['totp'] as String?;
          } else if (v is String) {
            return v;
          }
        }
      }
      return null;
    }

    String? findTotp() {
      for (final fm in allFields) {
        final type = (fm['type'] as String? ?? '').toUpperCase();
        final id = (fm['id'] as String? ?? '').toLowerCase();
        final title = (fm['title'] as String? ?? '').toLowerCase();
        if (type == 'OTP' || id.contains('totp') || id.contains('one-time') || title.contains('totp') || title.contains('one-time')) {
          final v = fm['value'];
          if (v is Map<String, dynamic>) {
            return v['totp'] as String? ?? v['string'] as String? ?? v['concealed'] as String?;
          } else if (v is String) {
            return v;
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
        for (final lf in loginFields) {
          final lfm = lf as Map<String, dynamic>;
          final designation = lfm['designation'] as String?;
          if (designation == 'username') username = lfm['value'] as String?;
          if (designation == 'password') password = lfm['value'] as String?;
        }
        final totp = findTotp();
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
          cardholderName: findField('cardholder') ?? findField('cardholder name'),
          cardNumber: findField('ccnum') ?? findField('number'),
          cardBrand: findField('type') ?? findField('brand'),
          cardExpiryMonth: int.tryParse(findField('expiry_mm') ?? findField('expiry month') ?? ''),
          cardExpiryYear: int.tryParse(findField('expiry_yy') ?? findField('expiry year') ?? ''),
          cardCvv: findField('cvv') ?? findField('code'),
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
          firstName: findField('firstname') ?? findField('first name'),
          lastName: findField('lastname') ?? findField('last name'),
          birthdate: findField('birthdate'),
          gender: findField('sex') ?? findField('gender'),
          street: findField('address1') ?? findField('street'),
          city: findField('city'),
          state: findField('state'),
          zip: findField('zip') ?? findField('postal code'),
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
