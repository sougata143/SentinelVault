/// Shared CSV parsing helpers for import parsers.

/// Parses [content] into a list of CSV rows, respecting RFC 4180 double-quoted
/// fields that may contain newlines, commas, or escaped quotes (`""`).
List<List<String>> parseCsvRows(String content) {
  final rows = <List<String>>[];
  final currentFields = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  var i = 0;

  while (i < content.length) {
    final ch = content[i];

    if (ch == '"') {
      if (inQuotes && i + 1 < content.length && content[i + 1] == '"') {
        buf.write('"');
        i += 2;
        continue;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == ',' && !inQuotes) {
      currentFields.add(buf.toString());
      buf.clear();
    } else if ((ch == '\n' || ch == '\r') && !inQuotes) {
      currentFields.add(buf.toString());
      buf.clear();
      if (currentFields.any((f) => f.trim().isNotEmpty)) {
        rows.add(List.from(currentFields));
      }
      currentFields.clear();
      if (ch == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
        i++;
      }
    } else {
      buf.write(ch);
    }
    i++;
  }

  if (buf.isNotEmpty || currentFields.isNotEmpty) {
    currentFields.add(buf.toString());
    if (currentFields.any((f) => f.trim().isNotEmpty)) {
      rows.add(currentFields);
    }
  }

  return rows;
}
