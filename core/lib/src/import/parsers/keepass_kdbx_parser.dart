import 'dart:typed_data';
import 'package:kdbx/kdbx.dart';
import '../import_result.dart';

/// Decrypts and parses a KeePass KDBX database (KDBX3 or KDBX4 format) into [ImportResult].
class KeePassKdbxParser {
  /// Decrypts and parses the raw KeePass database [bytes] using the provided [password]
  /// and optional [keyFileBytes] into an [ImportResult].
  Future<ImportResult> parse({
    required Uint8List bytes,
    required String password,
    Uint8List? keyFileBytes,
  }) async {
    final items = <ParsedItem>[];
    final errors = <ParsedError>[];

    final ProtectedValue protectedPassword = ProtectedValue.fromString(password);
    final credentials = Credentials.composite(protectedPassword, keyFileBytes);

    try {
      final kdbx = await KdbxFormat().read(bytes, credentials);
      final rootGroup = kdbx.body.rootGroup;
      _parseGroup(rootGroup, items, errors);
    } catch (e) {
      errors.add(ParsedError(sourceRef: 'root', reason: 'Failed to decrypt or parse KeePass database: $e'));
    } finally {
      // Security Invariant: Scrub sensitive password and key file material from memory immediately after use.
      try {
        protectedPassword.binaryValue.fillRange(0, protectedPassword.binaryValue.length, 0);
      } catch (_) {}
      if (keyFileBytes != null) {
        try {
          keyFileBytes.fillRange(0, keyFileBytes.length, 0);
        } catch (_) {}
      }
    }

    return ImportResult(items: items, errors: errors);
  }

  void _parseGroup(KdbxGroup group, List<ParsedItem> items, List<ParsedError> errors) {
    for (final entry in group.entries) {
      try {
        final title = entry.getString(KdbxKeyCommon.TITLE)?.getText();
        if (title == null || title.isEmpty) {
          errors.add(ParsedError(
            sourceRef: 'entry[${entry.uuid}]',
            reason: 'Missing title for entry, skipping.',
          ));
          continue;
        }

        final username = entry.getString(KdbxKeyCommon.USER_NAME)?.getText();
        final password = entry.getString(KdbxKeyCommon.PASSWORD)?.getText();
        final url = entry.getString(KdbxKeyCommon.URL)?.getText();
        final notes = entry.getString(KdbxKey('Notes'))?.getText();

        // Check standard custom fields for TOTP secrets
        final totp = entry.getString(KdbxKey('otp'))?.getText() ??
            entry.getString(KdbxKey('totp'))?.getText() ??
            entry.getString(KdbxKey('totpSecret'))?.getText();

        final List<String> urls = url != null && url.trim().isNotEmpty ? <String>[url.trim()] : const <String>[];

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
        errors.add(ParsedError(
          sourceRef: 'entry[${entry.uuid}]',
          reason: 'Failed to parse entry: $e',
        ));
      }
    }

    // Recursively parse subgroups
    for (final subGroup in group.groups) {
      _parseGroup(subGroup, items, errors);
    }
  }
}
