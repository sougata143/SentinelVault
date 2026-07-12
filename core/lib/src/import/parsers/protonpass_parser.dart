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

    // Check if it's the nested "vaults" structure
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
      // Flat items list inside map
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
      // Treat the map itself as a single item
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

      // Extract Title
      final title = metadata?['name'] ?? itemMap['name'] ?? itemMap['title'];
      if (title == null || (title is String && title.trim().isEmpty)) {
        errors.add(ParsedError(sourceRef: srcRef, reason: 'Missing item title.'));
        return;
      }

      // Extract Notes
      final notes = metadata?['note'] ?? metadata?['notes'] ?? itemMap['note'] ?? itemMap['notes'];

      // Extract Username
      final username = content?['username'] ?? itemMap['username'] ?? itemMap['email'];

      // Extract Password
      final password = content?['password'] ?? itemMap['password'];

      // Extract TOTP
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
