import 'dart:convert';
import '../models/vault_item.dart';
import '../models/models.dart';

/// Produces export payloads in two formats.
///
/// Security invariants:
/// - [buildSvaultBackup] operates on ciphertext only — it NEVER decrypts.
/// - [buildPlaintextCsv] and [buildPlaintextJson] receive already-decrypted
///   [VaultItem] objects and may only be called AFTER the caller has verified
///   master-password re-authentication. The ExportService itself has no
///   knowledge of passwords or keys.
/// - No method in this class sends data to any network endpoint.
/// - The caller is responsible for zeroing any in-memory plaintext lists
///   after calling the plaintext methods.
class ExportService {
  // ── Encrypted .svault Backup ─────────────────────────────────────────────

  /// Packages all [encryptedItems] ciphertext into a `.svault` archive.
  ///
  /// The output is a JSON-encoded byte list. It contains ONLY ciphertext blobs
  /// and metadata — nothing is decrypted. Safe to write to disk as-is.
  ///
  /// Returns the raw bytes of the `.svault` file.
  List<int> buildSvaultBackup(List<EncryptedVaultItem> encryptedItems) {
    final payload = {
      'format': 'svault',
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'item_count': encryptedItems.length,
      'items': encryptedItems.map((e) => e.toJson()).toList(),
    };
    return utf8.encode(jsonEncode(payload));
  }

  // ── Plaintext CSV Export ──────────────────────────────────────────────────

  /// Builds a CSV string from a list of fully-decrypted [VaultItem] objects.
  ///
  /// Security invariant: This method MUST only be called after the caller
  /// has successfully verified master-password re-authentication.
  /// The caller MUST set their plaintext item list to [] immediately after
  /// this method returns and the file has been handed to the download layer.
  ///
  /// Fields that are not applicable to an item type are left empty.
  String buildPlaintextCsv(List<VaultItem> decryptedItems) {
    final buf = StringBuffer();
    buf.writeln(
      'type,title,username,password,url,card_number,card_brand,'
      'expiry_month,expiry_year,cvv,cardholder,identity_name,'
      'street,city,state,zip,country,bank_name,account_number,'
      'routing_number,note_content,tags,favorite,notes',
    );

    for (final item in decryptedItems) {
      final f = item.fields;
      String csv(String? v) {
        if (v == null || v.isEmpty) return '';
        // RFC 4180: quote fields containing commas, quotes, or newlines
        if (v.contains(',') || v.contains('"') || v.contains('\n')) {
          return '"${v.replaceAll('"', '""')}"';
        }
        return v;
      }

      String row = '';
      switch (f.runtimeType) {
        case LoginFields:
          final lf = f as LoginFields;
          row = [
            csv('login'),
            csv(item.title),
            csv(lf.username),
            csv(lf.password.plaintext),
            csv(lf.urls.join(' | ')),
            '', '', '', '', '', '', '', '', '', '', '', '', '', '', // card/identity/bank empty
            '',
            csv(item.tags.join('|')),
            csv(item.favorite.toString()),
            csv(item.notes.plaintext),
          ].join(',');
          break;

        case CreditCardFields:
          final cf = f as CreditCardFields;
          row = [
            csv('credit_card'),
            csv(item.title),
            '', '', // username, password
            '', // url
            csv(cf.cardNumber.plaintext),
            csv(cf.brand),
            csv(cf.expiryMonth.toString()),
            csv(cf.expiryYear.toString()),
            csv(cf.cvv.plaintext),
            csv(cf.cardholderName),
            '', '', '', '', '', '', // identity fields
            '', '', // bank fields
            '',
            csv(item.tags.join('|')),
            csv(item.favorite.toString()),
            csv(item.notes.plaintext),
          ].join(',');
          break;

        case IdentityFields:
          final id = f as IdentityFields;
          row = [
            csv('identity'),
            csv(item.title),
            '', '', '', // username, password, url
            '', '', '', '', '', // card fields
            csv('${id.firstName} ${id.lastName}'.trim()),
            csv(id.address.street),
            csv(id.address.city),
            csv(id.address.state),
            csv(id.address.zip),
            csv(id.address.country),
            '', '', // bank fields
            '',
            csv(item.tags.join('|')),
            csv(item.favorite.toString()),
            csv(item.notes.plaintext),
          ].join(',');
          break;

        case SecureNoteFields:
          final sn = f as SecureNoteFields;
          row = [
            csv('secure_note'),
            csv(item.title),
            ...List.filled(17, ''), // most fields empty
            csv(sn.content.plaintext),
            csv(item.tags.join('|')),
            csv(item.favorite.toString()),
            csv(item.notes.plaintext),
          ].join(',');
          break;

        case BankAccountFields:
          final ba = f as BankAccountFields;
          row = [
            csv('bank_account'),
            csv(item.title),
            '', '', '', // username, password, url
            '', '', '', '', '', '', // card fields
            '', '', '', '', '', '', // identity fields
            csv(ba.bankName),
            csv(ba.accountNumber.plaintext),
            csv(ba.routingNumber.plaintext),
            '',
            csv(item.tags.join('|')),
            csv(item.favorite.toString()),
            csv(item.notes.plaintext),
          ].join(',');
          break;

        case PasswordFields:
          final pf = f as PasswordFields;
          row = [
            csv('password'),
            csv(item.title),
            '',
            csv(pf.password.plaintext),
            ...List.filled(18, ''),
            csv(item.tags.join('|')),
            csv(item.favorite.toString()),
            csv(item.notes.plaintext),
          ].join(',');
          break;

        default:
          // Unknown type — output a row with only the title
          row = [csv('unknown'), csv(item.title), ...List.filled(21, '')].join(',');
      }

      buf.writeln(row);
    }

    return buf.toString();
  }

  // ── Plaintext JSON Export ─────────────────────────────────────────────────

  /// Builds a JSON string from a list of fully-decrypted [VaultItem] objects.
  ///
  /// Same security constraints as [buildPlaintextCsv].
  String buildPlaintextJson(List<VaultItem> decryptedItems) {
    final result = {
      'format': 'sentinelvault_plaintext_export',
      'version': 1,
      'warning': 'THIS FILE IS UNENCRYPTED. Delete after use.',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'item_count': decryptedItems.length,
      'items': decryptedItems.map((item) {
        final base = {
          'type': item.type.toValue(),
          'title': item.title,
          'tags': item.tags,
          'favorite': item.favorite,
          'notes': item.notes.plaintext ?? '',
        };

        final f = item.fields;
        if (f is LoginFields) {
          base['fields'] = {
            'username': f.username,
            'password': f.password.plaintext ?? '',
            'urls': f.urls,
            'totp_secret': f.otpSecret.plaintext ?? '',
          };
        } else if (f is CreditCardFields) {
          base['fields'] = {
            'cardholder_name': f.cardholderName,
            'card_number': f.cardNumber.plaintext ?? '',
            'brand': f.brand,
            'expiry_month': f.expiryMonth,
            'expiry_year': f.expiryYear,
            'cvv': f.cvv.plaintext ?? '',
          };
        } else if (f is IdentityFields) {
          base['fields'] = {
            'first_name': f.firstName,
            'last_name': f.lastName,
            'street': f.address.street,
            'city': f.address.city,
            'state': f.address.state,
            'zip': f.address.zip,
            'country': f.address.country,
          };
        } else if (f is SecureNoteFields) {
          base['fields'] = {'content': f.content.plaintext ?? ''};
        } else if (f is BankAccountFields) {
          base['fields'] = {
            'bank_name': f.bankName,
            'account_number': f.accountNumber.plaintext ?? '',
            'routing_number': f.routingNumber.plaintext ?? '',
          };
        } else if (f is PasswordFields) {
          base['fields'] = {'password': f.password.plaintext ?? ''};
        }

        return base;
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(result);
  }
}
