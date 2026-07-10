import '../import_result.dart';

/// Parses a LastPass CSV export into [ImportResult].
///
/// All LastPass items map to the `login` type.
/// The expected CSV columns are:
///   url, username, password, totp, extra, name, grouping, fav
///
/// Security invariant: [csvContent] must be a string already in memory.
/// The file must never be saved to disk by the caller before passing here.
class LastPassParser {
  // Expected column names in LastPass CSV header
  static const _colUrl = 'url';
  static const _colUsername = 'username';
  static const _colPassword = 'password';
  static const _colTotp = 'totp';
  static const _colExtra = 'extra';
  static const _colName = 'name';
  static const _colFav = 'fav';

  ImportResult parse(String csvContent) {
    final items = <ParsedItem>[];
    final errors = <ParsedError>[];

    final lines = _splitLines(csvContent);
    if (lines.isEmpty) {
      errors.add(const ParsedError(sourceRef: 'root', reason: 'Empty CSV file.'));
      return ImportResult(items: items, errors: errors);
    }

    final header = _parseCsvRow(lines[0]);
    final colIndex = {for (var i = 0; i < header.length; i++) header[i].toLowerCase(): i};

    // Verify required columns
    for (final required in [_colName, _colPassword, _colUrl]) {
      if (!colIndex.containsKey(required)) {
        errors.add(ParsedError(
          sourceRef: 'header',
          reason: 'Required column "$required" not found in CSV header.',
        ));
        return ImportResult(items: items, errors: errors);
      }
    }

    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final row = _parseCsvRow(lines[i]);
      final srcRef = 'row[$i]';

      try {
        String? get(String col) {
          final idx = colIndex[col];
          if (idx == null || idx >= row.length) return null;
          final val = row[idx];
          return val.isEmpty ? null : val;
        }

        final name = get(_colName);
        if (name == null) {
          errors.add(ParsedError(sourceRef: srcRef, reason: 'Missing required "name" field.'));
          continue;
        }

        final favStr = get(_colFav) ?? '0';
        final fav = favStr == '1' || favStr.toLowerCase() == 'true';

        final url = get(_colUrl);
        final urls = url != null ? [url] : <String>[];

        items.add(ParsedItem(
          title: name,
          type: 'login',
          username: get(_colUsername),
          password: get(_colPassword),
          urls: urls,
          totpSecret: get(_colTotp),
          notes: get(_colExtra),
          favorite: fav,
        ));
      } catch (e) {
        errors.add(ParsedError(sourceRef: srcRef, reason: 'Unexpected error: $e'));
      }
    }

    return ImportResult(items: items, errors: errors);
  }

  List<String> _splitLines(String content) {
    return content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
  }

  /// Parses a single CSV row, respecting double-quoted fields that may contain commas.
  List<String> _parseCsvRow(String row) {
    final fields = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < row.length; i++) {
      final ch = row[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < row.length && row[i + 1] == '"') {
          // Escaped quote inside quoted field
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    fields.add(buf.toString());
    return fields;
  }
}
