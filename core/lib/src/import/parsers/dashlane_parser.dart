import '../import_result.dart';

/// Parses a Dashlane CSV export into [ImportResult].
class DashlaneParser {
  /// Parses a Dashlane CSV file [csvContent] containing accounts, logins, and passwords
  /// into an [ImportResult] containing parsed vault items and errors.
  ImportResult parse(String csvContent) {
    final items = <ParsedItem>[];
    final errors = <ParsedError>[];

    final lines = _splitLines(csvContent);
    if (lines.isEmpty) {
      errors.add(const ParsedError(sourceRef: 'root', reason: 'Empty CSV file.'));
      return ImportResult(items: items, errors: errors);
    }

    final header = _parseCsvRow(lines[0]);
    final colIndex = {for (var i = 0; i < header.length; i++) header[i].trim().toLowerCase(): i};

    // Helper to find column index from a list of candidate names
    int? findCol(List<String> candidates) {
      for (final c in candidates) {
        final idx = colIndex[c.toLowerCase()];
        if (idx != null) return idx;
      }
      return null;
    }

    final titleIdx = findCol(const ['title', 'name']);
    final usernameIdx = findCol(const ['username', 'login', 'email']);
    final passwordIdx = findCol(const ['password', 'pwd']);
    final urlIdx = findCol(const ['url', 'website']);
    final notesIdx = findCol(const ['notes', 'note', 'category']);
    final totpIdx = findCol(const ['otpsecret', 'totp', 'otp']);

    if (titleIdx == null) {
      errors.add(const ParsedError(
        sourceRef: 'header',
        reason: 'Required column "title" or "name" not found in Dashlane CSV header.',
      ));
      return ImportResult(items: items, errors: errors);
    }

    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final row = _parseCsvRow(lines[i]);
      final srcRef = 'row[$i]';

      try {
        String? getVal(int? idx) {
          if (idx == null || idx >= row.length) return null;
          final val = row[idx].trim();
          return val.isEmpty ? null : val;
        }

        final title = getVal(titleIdx);
        if (title == null) {
          errors.add(ParsedError(sourceRef: srcRef, reason: 'Missing required title field.'));
          continue;
        }

        final url = getVal(urlIdx);
        final urls = url != null ? [url] : <String>[];

        items.add(ParsedItem(
          title: title,
          type: 'login',
          username: getVal(usernameIdx),
          password: getVal(passwordIdx),
          urls: urls,
          totpSecret: getVal(totpIdx),
          notes: getVal(notesIdx),
          favorite: false,
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

  List<String> _parseCsvRow(String row) {
    final fields = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < row.length; i++) {
      final ch = row[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < row.length && row[i + 1] == '"') {
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
