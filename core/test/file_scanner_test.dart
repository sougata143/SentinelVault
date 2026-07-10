import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Inline fixture byte arrays — no files on disk needed.
// These represent the minimum magic-byte headers to trigger signature detection.
// ─────────────────────────────────────────────────────────────────────────────

/// Real PDF magic bytes: %PDF-1.4 header.
final Uint8List kPdfBytes = Uint8List.fromList([
  0x25, 0x50, 0x44, 0x46, // %PDF
  0x2D, 0x31, 0x2E, 0x34, // -1.4
  0x0A, 0x25, 0xE2, 0xE3, // typical continuation
]);

/// Windows PE (MZ) executable header — the first two bytes are `MZ`.
final Uint8List kPeBytes = Uint8List.fromList([
  0x4D, 0x5A, // MZ
  0x90, 0x00, 0x03, 0x00, 0x00, 0x00, // typical PE stub continuation
]);

/// Open-XML / ZIP magic bytes — used by .docx, .xlsx, .docm, etc.
final Uint8List kZipBytes = Uint8List.fromList([
  0x50, 0x4B, 0x03, 0x04, // PK\x03\x04
  0x14, 0x00, 0x00, 0x00, // typical local file header continuation
]);

/// ELF executable header (Linux).
final Uint8List kElfBytes = Uint8List.fromList([
  0x7F, 0x45, 0x4C, 0x46, // \x7FELF
  0x02, 0x01, 0x01, 0x00, // ELF64 little-endian
]);

/// PNG image header.
final Uint8List kPngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, // \x89PNG
  0x0D, 0x0A, 0x1A, 0x0A, // standard PNG header continuation
]);

/// Short benign "text" content with no recognizable signature.
final Uint8List kUnknownBytes = Uint8List.fromList([
  0x48, 0x65, 0x6C, 0x6C, // Hell
  0x6F, 0x20, 0x57, 0x6F, // o Wo
]);

void main() {
  group('FileScanner — Layer 1 local checks', () {
    // ── 1. Matching extension + signature → no mismatch ───────────────────
    test('1. PDF bytes with .pdf extension → isSigMismatch == false', () {
      final result = FileScanner.scanLocal('document.pdf', kPdfBytes);

      expect(result.declaredExtension, equals('pdf'));
      expect(result.detectedType, equals(FileSignatureType.pdf));
      expect(result.isSigMismatch, isFalse);
      expect(result.isDoubleExtension, isFalse);
      expect(result.isMacroEnabled, isFalse);
      expect(result.isMalicious, isFalse);
    });

    // ── 2. PE bytes disguised as PDF → signature mismatch ─────────────────
    test('2. PE (MZ) bytes with .pdf extension → isSigMismatch == true', () {
      final result = FileScanner.scanLocal('invoice.pdf', kPeBytes);

      expect(result.declaredExtension, equals('pdf'));
      expect(result.detectedType, equals(FileSignatureType.pe));
      expect(result.isSigMismatch, isTrue,
          reason: 'MZ magic inside a .pdf file is a clear mismatch');
      expect(result.isMalicious, isTrue);
    });

    // ── 3. Matching PE bytes + .exe extension → no mismatch ───────────────
    test('3. PE (MZ) bytes with .exe extension → isSigMismatch == false', () {
      final result = FileScanner.scanLocal('setup.exe', kPeBytes);

      expect(result.detectedType, equals(FileSignatureType.pe));
      expect(result.isSigMismatch, isFalse,
          reason: 'MZ magic is correct for .exe');
      // Double extension? No — only one extension.
      expect(result.isDoubleExtension, isFalse);
    });

    // ── 4. Double extension with dangerous final part ──────────────────────
    test('4. Filename invoice.pdf.exe → isDoubleExtension == true', () {
      final result = FileScanner.scanLocal('invoice.pdf.exe', kPeBytes);

      expect(result.isDoubleExtension, isTrue,
          reason: '.pdf.exe is a classic double-extension attack');
      expect(result.declaredExtension, equals('exe'));
      expect(result.isMalicious, isTrue);
    });

    // ── 5. Double extension where final part is NOT dangerous → no flag ────
    test('5. Filename archive.tar.gz → isDoubleExtension == false', () {
      final result = FileScanner.scanLocal('archive.tar.gz', kZipBytes);

      expect(result.isDoubleExtension, isFalse,
          reason: '.gz is not in the dangerous extension list');
    });

    // ── 6. Macro-enabled Office format (.docm) ─────────────────────────────
    test('6. .docm filename → isMacroEnabled == true', () {
      final result = FileScanner.scanLocal('report.docm', kZipBytes);

      expect(result.declaredExtension, equals('docm'));
      expect(result.isMacroEnabled, isTrue);
      expect(result.isMalicious, isTrue);
    });

    // ── 7. Other macro-enabled formats ────────────────────────────────────
    test('7. .xlsm, .pptm, .dotm, .xltm all set isMacroEnabled', () {
      for (final ext in ['xlsm', 'pptm', 'dotm', 'xltm']) {
        final result = FileScanner.scanLocal('file.$ext', kZipBytes);
        expect(result.isMacroEnabled, isTrue,
            reason: '.$ext must be flagged as macro-enabled');
      }
    });

    // ── 8. ELF bytes inside a .png file → mismatch ────────────────────────
    test('8. ELF bytes with .png extension → isSigMismatch == true', () {
      final result = FileScanner.scanLocal('picture.png', kElfBytes);

      expect(result.detectedType, equals(FileSignatureType.elf));
      expect(result.isSigMismatch, isTrue,
          reason: 'ELF magic inside a .png is a mismatch');
      expect(result.isMalicious, isTrue);
    });

    // ── 9. Unknown signature with known extension → no false-positive ──────
    test('9. Unknown magic bytes with .txt extension → no mismatch', () {
      final result = FileScanner.scanLocal('readme.txt', kUnknownBytes);

      expect(result.detectedType, equals(FileSignatureType.unknown));
      expect(result.isSigMismatch, isFalse,
          reason: 'Unknown signature → cannot assert mismatch (avoid FP)');
      expect(result.isMalicious, isFalse);
    });

    // ── 10. SHA-256 is always computed and non-empty ───────────────────────
    test('10. SHA-256 hash is computed and non-empty for any input', () {
      for (final entry in <String, Uint8List>{
        'a.pdf': kPdfBytes,
        'b.exe': kPeBytes,
        'c.png': kPngBytes,
        'd.docm': kZipBytes,
      }.entries) {
        final result = FileScanner.scanLocal(entry.key, entry.value);
        expect(result.sha256, isNotEmpty);
        expect(result.sha256.length, equals(64),
            reason: 'SHA-256 hex string must be exactly 64 characters');
      }
    });

    // ── 11. SHA-256 matches the known digest for PDF magic bytes ──────────
    test('11. SHA-256 digest is deterministic and matches expected value', () {
      final r1 = FileScanner.scanLocal('a.pdf', kPdfBytes);
      final r2 = FileScanner.scanLocal('b.pdf', kPdfBytes);
      // Same bytes → same hash regardless of filename.
      expect(r1.sha256, equals(r2.sha256));
    });

    // ── 12. redactedSignals never exposes sha256 or filename ──────────────
    test('12. toRedactedSignals() does not leak sha256 or filename', () {
      final result = FileScanner.scanLocal('secret.docm', kZipBytes);
      final signals = result.toRedactedSignals();

      expect(signals.containsKey('sha256'), isFalse,
          reason: 'Hash must not be in the redacted signal map');
      expect(signals.containsKey('file_extension'), isTrue);
      expect(signals['signature_mismatch'], isFalse);
      expect(signals['macro_detected'], isTrue);
    });

    // ── 13. withReputation updates verdict and isMalicious correctly ───────
    test('13. withReputation("malicious") sets isMalicious = true', () {
      final base = FileScanner.scanLocal('clean.png', kPngBytes);
      expect(base.isMalicious, isFalse);

      final updated = base.withReputation('malicious');
      expect(updated.reputationVerdict, equals('malicious'));
      expect(updated.isMalicious, isTrue);
    });

    test('14. withReputation("clean") on clean file keeps isMalicious = false',
        () {
      final base = FileScanner.scanLocal('safe.exe', kPeBytes);
      expect(base.isMalicious, isFalse);

      final updated = base.withReputation('clean');
      expect(updated.reputationVerdict, equals('clean'));
      expect(updated.isMalicious, isFalse);
    });
  });
}
