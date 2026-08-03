import '../csv_helpers.dart';
import '../import_result.dart';

/// Parses a LastPass CSV export into [ImportResult].
///
/// LastPass CSV header schema:
///   url,username,password,totp,extra,name,grouping,fav
class LastPassParser {
  static const _colUrl = 'url';
  static const _colUsername = 'username';
  static const _colPassword = 'password';
  static const _colTotp = 'totp';
  static const _colExtra = 'extra';
  static const _colName = 'name';
  static const _colFav = 'fav';
  static const _colGrouping = 'grouping';

  /// Parses LastPass CSV content [csvContent] into parsed items and errors.
  ImportResult parse(String csvContent) {
    final items = <ParsedItem>[];
    final errors = <ParsedError>[];

    final rows = parseCsvRows(csvContent);
    if (rows.isEmpty) {
      errors.add(const ParsedError(sourceRef: 'root', reason: 'Empty CSV file.'));
      return ImportResult(items: items, errors: errors);
    }

    final header = rows[0];
    final colIndex = {for (var i = 0; i < header.length; i++) header[i].trim().toLowerCase(): i};

    // Verify required column "name"
    if (!colIndex.containsKey(_colName)) {
      errors.add(const ParsedError(
        sourceRef: 'header',
        reason: 'Required column "name" not found in CSV header.',
      ));
      return ImportResult(items: items, errors: errors);
    }

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((f) => f.trim().isEmpty)) continue;
      final srcRef = 'row[$i]';

      try {
        String? get(String col) {
          final idx = colIndex[col];
          if (idx == null || idx >= row.length) return null;
          final val = row[idx].trim();
          return val.isEmpty ? null : val;
        }

        final name = get(_colName);
        if (name == null) {
          errors.add(ParsedError(sourceRef: srcRef, reason: 'Missing required "name" field.'));
          continue;
        }

        final favStr = get(_colFav) ?? '0';
        final fav = favStr == '1' || favStr.toLowerCase() == 'true';
        final grouping = get(_colGrouping);
        final tags = grouping != null ? <String>[grouping] : <String>[];

        final url = get(_colUrl);
        final password = get(_colPassword);
        final username = get(_colUsername);
        final extra = get(_colExtra);
        final totp = get(_colTotp);

        // Detect Secure Note
        if ((url != null && url.startsWith('http://sn')) || (password == null && username == null && extra != null && extra.isNotEmpty)) {
          items.add(ParsedItem(
            title: name,
            type: 'secure_note',
            noteContent: extra,
            notes: null,
            tags: tags,
            favorite: fav,
          ));
          continue;
        }

        final urls = url != null ? [url] : <String>[];

        items.add(ParsedItem(
          title: name,
          type: 'login',
          username: username,
          password: password,
          urls: urls,
          totpSecret: totp,
          notes: extra,
          tags: tags,
          favorite: fav,
        ));
      } catch (e) {
        errors.add(ParsedError(sourceRef: srcRef, reason: 'Unexpected error: $e'));
      }
    }

    return ImportResult(items: items, errors: errors);
  }
}
