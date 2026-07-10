import '../import_result.dart';

/// Parses a generic CSV export with a user-provided column mapping.
///
/// [columnMapping] maps target field names to actual CSV column headers.
/// Supported target field names:
///   'title', 'username', 'password', 'url', 'notes', 'totp', 'favorite'
///
/// Items missing a 'title' are flagged as errors.
/// Columns present in the CSV but not in [columnMapping] are flagged as
/// unmapped warnings — never silently dropped.
class GenericCsvParser {
  final Map<String, String> columnMapping;

  const GenericCsvParser({required this.columnMapping});

  ImportResult parse(String csvContent) {
    final items = <ParsedItem>[];
    final errors = <ParsedError>[];

    final lines = _splitLines(csvContent);
    if (lines.isEmpty) {
      errors.add(const ParsedError(sourceRef: 'root', reason: 'Empty CSV file.'));
      return ImportResult(items: items, errors: errors);
    }

    final header = _parseCsvRow(lines[0]);
    final colIndex = {for (var i = 0; i < header.length; i++) header[i].trim(): i};

    // Check for unmapped columns — flag but continue
    for (final col in header) {
      final c = col.trim();
      if (c.isEmpty) continue;
      final isMapped = columnMapping.values.any((v) => v.toLowerCase() == c.toLowerCase());
      if (!isMapped) {
        errors.add(ParsedError(
          sourceRef: 'header',
          reason: 'Column "$c" is not mapped and will be ignored.',
        ));
      }
    }

    // Build reverse mapping: CSV column name → target field name
    final reverseMapping = <String, String>{};
    for (final entry in columnMapping.entries) {
      reverseMapping[entry.value.toLowerCase()] = entry.key;
    }

    String? getField(List<String> row, String targetField) {
      final csvCol = columnMapping[targetField];
      if (csvCol == null) return null;
      final idx = colIndex[csvCol];
      if (idx == null || idx >= row.length) return null;
      final val = row[idx].trim();
      return val.isEmpty ? null : val;
    }

    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final row = _parseCsvRow(lines[i]);
      final srcRef = 'row[$i]';

      try {
        final title = getField(row, 'title');
        if (title == null) {
          errors.add(ParsedError(
            sourceRef: srcRef,
            reason: 'Missing required "title" field (not mapped or empty).',
          ));
          continue;
        }

        final favStr = getField(row, 'favorite') ?? '0';
        final fav = favStr == '1' || favStr.toLowerCase() == 'true';

        final url = getField(row, 'url');
        final urls = url != null ? [url] : <String>[];

        items.add(ParsedItem(
          title: title,
          type: 'login', // Generic CSV always maps to login
          username: getField(row, 'username'),
          password: getField(row, 'password'),
          urls: urls,
          totpSecret: getField(row, 'totp'),
          notes: getField(row, 'notes'),
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
