import '../import_result.dart';

/// Parses a RoboForm CSV export into [ImportResult].
class RoboFormParser {
  /// Parses RoboForm CSV content [csvContent] into parsed items and errors.
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

    int? findCol(List<String> candidates) {
      for (final c in candidates) {
        final idx = colIndex[c.toLowerCase()];
        if (idx != null) return idx;
      }
      return null;
    }

    final titleIdx = findCol(const ['name', 'title']);
    final usernameIdx = findCol(const ['login', 'username']);
    final passwordIdx = findCol(const ['pwd', 'password']);
    final urlIdx = findCol(const ['url']);
    final notesIdx = findCol(const ['note', 'notes']);

    if (titleIdx == null) {
      errors.add(const ParsedError(
        sourceRef: 'header',
        reason: 'Required column "Name" or "title" not found in RoboForm CSV header.',
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
