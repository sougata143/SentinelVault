import '../csv_helpers.dart';
import '../import_result.dart';

/// Parses a NordPass CSV export into [ImportResult].
///
/// Supported columns per NordPass export schema:
/// `name,url,username,password,note,cardholdername,cardnumber,cvc,expirydate,zipcode,folder,full_name,phone_number,email,address1,address2,city,country,state,totp,shared_folder`
class NordPassParser {
  /// Parses NordPass CSV content [csvContent] into parsed items and errors.
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

    final nameIdx = findCol(const ['name', 'title']);
    final urlIdx = findCol(const ['url']);
    final usernameIdx = findCol(const ['username']);
    final passwordIdx = findCol(const ['password']);
    final noteIdx = findCol(const ['note', 'notes']);

    final cardholderIdx = findCol(const ['cardholdername']);
    final cardnumberIdx = findCol(const ['cardnumber']);
    final cvcIdx = findCol(const ['cvc']);
    final expiryIdx = findCol(const ['expirydate']);

    final fullNameIdx = findCol(const ['full_name']);
    final phoneIdx = findCol(const ['phone_number']);
    final emailIdx = findCol(const ['email']);
    final address1Idx = findCol(const ['address1']);
    final address2Idx = findCol(const ['address2']);
    final cityIdx = findCol(const ['city']);
    final countryIdx = findCol(const ['country']);
    final stateIdx = findCol(const ['state']);
    final zipIdx = findCol(const ['zipcode']);

    final totpIdx = findCol(const ['totp']);
    final folderIdx = findCol(const ['folder']);

    if (nameIdx == null && fullNameIdx == null) {
      errors.add(const ParsedError(
        sourceRef: 'header',
        reason: 'Required column "name" or "full_name" not found in NordPass CSV header.',
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

        final name = getVal(nameIdx);
        final fullName = getVal(fullNameIdx);
        final url = getVal(urlIdx);
        final username = getVal(usernameIdx);
        final password = getVal(passwordIdx);
        final note = getVal(noteIdx);
        final email = getVal(emailIdx);

        final cardholder = getVal(cardholderIdx);
        final cardnumber = getVal(cardnumberIdx);
        final cvc = getVal(cvcIdx);
        final expiry = getVal(expiryIdx);

        final phone = getVal(phoneIdx);
        final address1 = getVal(address1Idx);
        final address2 = getVal(address2Idx);
        final city = getVal(cityIdx);
        final state = getVal(stateIdx);
        final zip = getVal(zipIdx);
        final country = getVal(countryIdx);

        final totp = getVal(totpIdx);
        final folder = getVal(folderIdx);
        final tags = folder != null ? <String>[folder] : <String>[];

        final title = name ?? fullName ?? url ?? 'Untitled Item';

        // 1. Credit Card Item
        if (cardnumber != null || cardholder != null || cvc != null || expiry != null) {
          int? expMonth;
          int? expYear;
          if (expiry != null) {
            final parts = expiry.split(RegExp(r'[/.-]'));
            if (parts.length >= 2) {
              expMonth = int.tryParse(parts[0].trim());
              final yr = int.tryParse(parts[1].trim());
              if (yr != null) {
                expYear = yr < 100 ? 2000 + yr : yr;
              }
            }
          }
          items.add(ParsedItem(
            title: title,
            type: 'credit_card',
            cardholderName: cardholder,
            cardNumber: cardnumber,
            cardCvv: cvc,
            cardExpiryMonth: expMonth,
            cardExpiryYear: expYear,
            notes: note,
            tags: tags,
            favorite: false,
          ));
          continue;
        }

        // 2. Personal Info / Identity Item
        if (fullName != null || address1 != null || (phone != null && password == null && url == null)) {
          String? firstName;
          String? lastName;
          if (fullName != null) {
            final parts = fullName.trim().split(RegExp(r'\s+'));
            if (parts.isNotEmpty) {
              firstName = parts.first;
              if (parts.length > 1) {
                lastName = parts.sublist(1).join(' ');
              }
            }
          }
          final street = [if (address1 != null) address1, if (address2 != null) address2].join(', ');
          final noteParts = [if (note != null) note, if (phone != null) 'Phone: $phone'].join('\n');

          items.add(ParsedItem(
            title: title,
            type: 'identity',
            firstName: firstName,
            lastName: lastName,
            username: email,
            street: street.isEmpty ? null : street,
            city: city,
            state: state,
            zip: zip,
            country: country,
            notes: noteParts.isEmpty ? null : noteParts,
            tags: tags,
            favorite: false,
          ));
          continue;
        }

        // 3. Secure Note Item
        if (note != null && password == null && username == null && email == null && url == null) {
          items.add(ParsedItem(
            title: title,
            type: 'secure_note',
            noteContent: note,
            notes: null,
            tags: tags,
            favorite: false,
          ));
          continue;
        }

        // 4. Login Item (Default)
        final effectiveUsername = username ?? email;
        final urls = url != null ? [url] : <String>[];

        items.add(ParsedItem(
          title: title,
          type: 'login',
          username: effectiveUsername,
          password: password,
          urls: urls,
          totpSecret: totp,
          notes: note,
          tags: tags,
          favorite: false,
        ));
      } catch (e) {
        errors.add(ParsedError(sourceRef: srcRef, reason: 'Unexpected error: $e'));
      }
    }

    return ImportResult(items: items, errors: errors);
  }
}
