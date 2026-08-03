import 'dart:convert';
import '../import_result.dart';

/// Parses a Proton Pass JSON export into [ImportResult].
class ProtonPassParser {
  /// Parses Proton Pass JSON export content [jsonContent] into parsed items and errors.
  ImportResult parse(String jsonContent) {
    final items = <ParsedItem>[];
    final errors = <ParsedError>[];

    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(jsonContent);
      if (parsed is List) {
        for (var i = 0; i < parsed.length; i++) {
          final entry = parsed[i];
          if (entry is Map<String, dynamic>) {
            _parseItemMap(entry, items, errors, 'item[$i]');
          } else {
            errors.add(ParsedError(sourceRef: 'item[$i]', reason: 'Invalid item format: expected map.'));
          }
        }
        return ImportResult(items: items, errors: errors);
      } else if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      } else {
        errors.add(const ParsedError(sourceRef: 'root', reason: 'Invalid JSON format: expected list or map.'));
        return ImportResult(items: items, errors: errors);
      }
    } catch (e) {
      errors.add(ParsedError(sourceRef: 'root', reason: 'Invalid JSON: $e'));
      return ImportResult(items: items, errors: errors);
    }

    if (decoded.containsKey('vaults')) {
      final vaults = decoded['vaults'];
      if (vaults is List) {
        for (var vIdx = 0; vIdx < vaults.length; vIdx++) {
          final vault = vaults[vIdx];
          if (vault is Map<String, dynamic>) {
            final vaultName = vault['name'] ?? 'Vault $vIdx';
            final vaultItems = vault['items'];
            if (vaultItems is List) {
              for (var iIdx = 0; iIdx < vaultItems.length; iIdx++) {
                final item = vaultItems[iIdx];
                if (item is Map<String, dynamic>) {
                  _parseItemMap(item, items, errors, 'vault["$vaultName"].item[$iIdx]');
                }
              }
            }
          }
        }
      }
    } else if (decoded.containsKey('items')) {
      final flatItems = decoded['items'];
      if (flatItems is List) {
        for (var i = 0; i < flatItems.length; i++) {
          final item = flatItems[i];
          if (item is Map<String, dynamic>) {
            _parseItemMap(item, items, errors, 'items[$i]');
          }
        }
      }
    } else {
      _parseItemMap(decoded, items, errors, 'root');
    }

    return ImportResult(items: items, errors: errors);
  }

  void _parseItemMap(
    Map<String, dynamic> itemMap,
    List<ParsedItem> items,
    List<ParsedError> errors,
    String srcRef,
  ) {
    try {
      final data = itemMap['data'] as Map<String, dynamic>?;
      final metadata = data?['metadata'] as Map<String, dynamic>?;
      final content = data?['content'] as Map<String, dynamic>?;

      // Type String from metadata, data, or root
      final typeStr = (metadata?['type'] ?? data?['type'] ?? itemMap['type'] ?? '').toString().toLowerCase();

      // Title
      final title = metadata?['name'] ?? itemMap['name'] ?? itemMap['title'];
      if (title == null || (title is String && title.trim().isEmpty)) {
        errors.add(ParsedError(sourceRef: srcRef, reason: 'Missing item title.'));
        return;
      }

      // Notes
      final notes = metadata?['note'] ?? metadata?['notes'] ?? itemMap['note'] ?? itemMap['notes'];

      // Extract Username, Password, TOTP
      final username = content?['username'] ?? itemMap['username'] ?? itemMap['email'];
      final password = content?['password'] ?? itemMap['password'];
      final totp = content?['totpUri'] ?? content?['totp'] ?? itemMap['totp'] ?? itemMap['otp'];

      // Extract URLs
      final urls = <String>[];
      final contentUrls = content?['urls'];
      if (contentUrls is List) {
        for (final u in contentUrls) {
          if (u is String && u.trim().isNotEmpty) {
            urls.add(u.trim());
          }
        }
      } else if (contentUrls is String && contentUrls.trim().isNotEmpty) {
        urls.add(contentUrls.trim());
      } else {
        final flatUrl = itemMap['url'] ?? itemMap['website'];
        if (flatUrl is String && flatUrl.trim().isNotEmpty) {
          urls.add(flatUrl.trim());
        }
      }

      // 1. Note / Secure Note
      if (typeStr == 'note' || (notes != null && password == null && username == null && urls.isEmpty && typeStr != 'creditcard')) {
        items.add(ParsedItem(
          title: title.toString().trim(),
          type: 'secure_note',
          noteContent: notes?.toString().trim(),
          notes: null,
          favorite: itemMap['favorite'] == true || itemMap['fav'] == true,
        ));
        return;
      }

      // 2. Credit Card
      if (typeStr == 'creditcard' || typeStr == 'card') {
        final cardholder = content?['cardholderName'] ?? itemMap['cardholderName'];
        final number = content?['number'] ?? itemMap['number'];
        final cvv = content?['cvv'] ?? itemMap['cvv'];
        final expDate = content?['expirationDate'] ?? itemMap['expirationDate'];

        int? expMonth;
        int? expYear;
        if (expDate != null) {
          final parts = expDate.toString().split(RegExp(r'[/.-]'));
          if (parts.length >= 2) {
            expMonth = int.tryParse(parts[0].trim());
            final yr = int.tryParse(parts[1].trim());
            if (yr != null) expYear = yr < 100 ? 2000 + yr : yr;
          }
        }

        items.add(ParsedItem(
          title: title.toString().trim(),
          type: 'credit_card',
          cardholderName: cardholder?.toString().trim(),
          cardNumber: number?.toString().trim(),
          cardCvv: cvv?.toString().trim(),
          cardExpiryMonth: expMonth,
          cardExpiryYear: expYear,
          notes: notes?.toString().trim(),
          favorite: itemMap['favorite'] == true || itemMap['fav'] == true,
        ));
        return;
      }

      // 3. Login / Alias (Default)
      items.add(ParsedItem(
        title: title.toString().trim(),
        type: 'login',
        username: username?.toString().trim(),
        password: password?.toString(),
        urls: urls,
        totpSecret: totp?.toString().trim(),
        notes: notes?.toString().trim(),
        favorite: itemMap['favorite'] == true || itemMap['fav'] == true,
      ));
    } catch (e) {
      errors.add(ParsedError(sourceRef: srcRef, reason: 'Failed to parse item map: $e'));
    }
  }
}
