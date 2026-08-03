import '../csv_helpers.dart';
import '../import_result.dart';

/// Parses a Keeper CSV export into [ImportResult].
class KeeperParser {
  /// Parses Keeper CSV content [csvContent] into parsed items and errors.
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

    int? findCol(List<String> candidates) {
      for (final c in candidates) {
        final idx = colIndex[c.toLowerCase()];
        if (idx != null) return idx;
      }
      return null;
    }

    final titleIdx = findCol(const ['title', 'name', 'folder']);
    final usernameIdx = findCol(const ['login', 'username', 'login name']);
    final passwordIdx = findCol(const ['password', 'pwd']);
    final urlIdx = findCol(const ['website address', 'url', 'website']);
    final notesIdx = findCol(const ['notes', 'note']);

    if (titleIdx == null) {
      errors.add(const ParsedError(
        sourceRef: 'header',
        reason: 'Required column "Title" not found in Keeper CSV header.',
      ));
      return ImportResult(items: items, errors: errors);
    }

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((f) => f.trim().isEmpty)) continue;
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
        final username = getVal(usernameIdx);
        final password = getVal(passwordIdx);
        final notes = getVal(notesIdx);

        // Secure Note detection
        if (notes != null && password == null && username == null && url == null) {
          items.add(ParsedItem(
            title: title,
            type: 'secure_note',
            noteContent: notes,
            notes: null,
            favorite: false,
          ));
          continue;
        }

        final urls = url != null ? [url] : <String>[];

        items.add(ParsedItem(
          title: title,
          type: 'login',
          username: username,
          password: password,
          urls: urls,
          notes: notes,
          favorite: false,
        ));
      } catch (e) {
        errors.add(ParsedError(sourceRef: srcRef, reason: 'Unexpected error: $e'));
      }
    }

    return ImportResult(items: items, errors: errors);
  }
}
