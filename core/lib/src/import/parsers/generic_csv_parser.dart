import '../csv_helpers.dart';
import '../import_result.dart';

/// Parses a generic CSV export with a user-provided column mapping.
///
/// [columnMapping] maps target field names to actual CSV column headers.
/// Supported target field names:
///   'title', 'username', 'password', 'url', 'notes', 'totp', 'favorite'
class GenericCsvParser {
  /// The user-provided map that links CSV headers (values) to standard vault fields (keys).
  final Map<String, String> columnMapping;

  /// Creates a [GenericCsvParser] with the specified [columnMapping].
  const GenericCsvParser({required this.columnMapping});

  /// Parses generic CSV file [csvContent] based on [columnMapping] into an [ImportResult].
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

    // Check for unmapped columns — flag but continue
    for (final col in header) {
      final c = col.trim();
      if (c.isEmpty) continue;
      final isMapped = columnMapping.values.any((v) => v.trim().toLowerCase() == c.toLowerCase());
      if (!isMapped) {
        errors.add(ParsedError(
          sourceRef: 'header',
          reason: 'Column "$c" is not mapped and will be ignored.',
        ));
      }
    }

    String? getField(List<String> row, String targetField) {
      final csvCol = columnMapping[targetField];
      if (csvCol == null) return null;
      final idx = colIndex[csvCol.trim().toLowerCase()];
      if (idx == null || idx >= row.length) return null;
      final val = row[idx].trim();
      return val.isEmpty ? null : val;
    }

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((f) => f.trim().isEmpty)) continue;
      final srcRef = 'row[$i]';

      try {
        var title = getField(row, 'title');
        title ??= getField(row, 'url');
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
          type: 'login',
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
}
