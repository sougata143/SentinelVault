import '../csv_helpers.dart';
import '../import_result.dart';

/// Parses a Dashlane CSV export into [ImportResult].
class DashlaneParser {
  /// Parses a Dashlane CSV file [csvContent] into an [ImportResult].
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

    final titleIdx = findCol(const ['title', 'name']);
    final usernameIdx = findCol(const ['username', 'login', 'email']);
    final passwordIdx = findCol(const ['password', 'pwd']);
    final urlIdx = findCol(const ['url', 'website']);
    final notesIdx = findCol(const ['notes', 'note', 'category']);
    final totpIdx = findCol(const ['otpsecret', 'totp', 'otp']);

    final cardNumberIdx = findCol(const ['cardnumber', 'number']);
    final cardholderIdx = findCol(const ['cardholdername', 'cardholder']);

    if (titleIdx == null) {
      errors.add(const ParsedError(
        sourceRef: 'header',
        reason: 'Required column "title" or "name" not found in Dashlane CSV header.',
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
        final totp = getVal(totpIdx);
        final cardNumber = getVal(cardNumberIdx);
        final cardholder = getVal(cardholderIdx);

        // Credit Card detection
        if (cardNumber != null || cardholder != null) {
          items.add(ParsedItem(
            title: title,
            type: 'credit_card',
            cardholderName: cardholder,
            cardNumber: cardNumber,
            notes: notes,
            favorite: false,
          ));
          continue;
        }

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
          totpSecret: totp,
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
