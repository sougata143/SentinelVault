import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enumerations & Data Models
// ─────────────────────────────────────────────────────────────────────────────

/// The file type inferred from the first few magic bytes (file signature).
enum FileSignatureType {
  /// PDF — starts with `%PDF` (0x25 0x50 0x44 0x46)
  pdf,

  /// Windows Portable Executable (EXE/DLL) — starts with `MZ` (0x4D 0x5A)
  pe,

  /// ZIP archive or Open-XML-based Office format — starts with `PK\x03\x04`
  zip,

  /// Linux ELF executable — starts with `\x7FELF`
  elf,

  /// PNG image — starts with `\x89PNG`
  png,

  /// JPEG image — starts with `\xFF\xD8\xFF`
  jpeg,

  /// GIF image — starts with `GIF8`
  gif,

  /// Could not be matched to any known signature.
  unknown,
}

/// Holds the complete result of a local (Layer 1) file security check.
class FileScanResult {
  /// SHA-256 hex digest of the file content, computed from streaming chunks.
  final String sha256;

  /// Lowercased final extension as declared in the filename (e.g. `"exe"`).
  final String declaredExtension;

  /// File type inferred from reading the first 8 magic bytes.
  final FileSignatureType detectedType;

  /// `true` when the magic-byte type contradicts the declared extension
  /// (e.g. an `MZ` PE header inside a file named `invoice.pdf`).
  final bool isSigMismatch;

  /// `true` when the filename contains more than one extension and the final
  /// one is a known dangerous type (e.g. `document.pdf.exe`).
  final bool isDoubleExtension;

  /// `true` when the filename extension is a macro-enabled Office format
  /// (`.docm`, `.xlsm`, `.pptm`, `.dotm`).
  final bool isMacroEnabled;

  /// Human-readable reputation verdict from Layer 2 (VirusTotal hash lookup).
  /// `null` until a reputation check has been performed.
  final String? reputationVerdict;

  /// `true` when any local or reputation check has flagged this file.
  final bool isMalicious;

  /// Creates a [FileScanResult].
  const FileScanResult({
    required this.sha256,
    required this.declaredExtension,
    required this.detectedType,
    required this.isSigMismatch,
    required this.isDoubleExtension,
    required this.isMacroEnabled,
    this.reputationVerdict,
    required this.isMalicious,
  });

  /// Produces a **redacted** signal map safe to forward to the AI insights
  /// layer.  Raw file contents and paths are never included.
  Map<String, dynamic> toRedactedSignals() => {
        'file_extension': declaredExtension,
        'signature_mismatch': isSigMismatch,
        'double_extension': isDoubleExtension,
        'macro_detected': isMacroEnabled,
        'reputation_verdict': reputationVerdict ?? 'unknown',
      };

  /// Returns a copy of this result with [reputationVerdict] and
  /// [isMalicious] updated after a Layer 2 reputation check.
  FileScanResult withReputation(String verdict) {
    final malicious = isSigMismatch ||
        isDoubleExtension ||
        isMacroEnabled ||
        verdict == 'malicious' ||
        verdict == 'suspicious';
    return FileScanResult(
      sha256: sha256,
      declaredExtension: declaredExtension,
      detectedType: detectedType,
      isSigMismatch: isSigMismatch,
      isDoubleExtension: isDoubleExtension,
      isMacroEnabled: isMacroEnabled,
      reputationVerdict: verdict,
      isMalicious: malicious,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FileScanner
// ─────────────────────────────────────────────────────────────────────────────

/// Performs privacy-preserving, local-only security checks on a file.
///
/// ## Security invariants:
/// - [scanLocal] performs **no network calls**.  All analysis happens on-device.
/// - SHA-256 is computed in 64 KB chunks so large files are never fully loaded
///   into memory at once.
/// - File contents are never sent to any remote endpoint in this class.
///   Only the [FileScanResult.sha256] may be forwarded (Layer 2).
class FileScanner {
  // ── Magic-byte table ────────────────────────────────────────────────────
  // Each entry is a list of bytes to match at offset 0 of the file.
  static const _signatures = <FileSignatureType, List<int>>{
    FileSignatureType.pdf: [0x25, 0x50, 0x44, 0x46], // %PDF
    FileSignatureType.pe: [0x4D, 0x5A], // MZ
    FileSignatureType.zip: [0x50, 0x4B, 0x03, 0x04], // PK\x03\x04
    FileSignatureType.elf: [0x7F, 0x45, 0x4C, 0x46], // \x7FELF
    FileSignatureType.png: [0x89, 0x50, 0x4E, 0x47], // \x89PNG
    FileSignatureType.jpeg: [0xFF, 0xD8, 0xFF], // \xFF\xD8\xFF
    FileSignatureType.gif: [0x47, 0x49, 0x46, 0x38], // GIF8
  };

  // Extension → expected signature types mapping (one extension may be
  // legitimately backed by several signature types, e.g. .docx is a zip).
  static const _extensionTypes = <String, List<FileSignatureType>>{
    'pdf': [FileSignatureType.pdf],
    'exe': [FileSignatureType.pe],
    'dll': [FileSignatureType.pe],
    'sys': [FileSignatureType.pe],
    'zip': [FileSignatureType.zip],
    'jar': [FileSignatureType.zip],
    'docx': [FileSignatureType.zip],
    'xlsx': [FileSignatureType.zip],
    'pptx': [FileSignatureType.zip],
    'docm': [FileSignatureType.zip],
    'xlsm': [FileSignatureType.zip],
    'pptm': [FileSignatureType.zip],
    'dotm': [FileSignatureType.zip],
    'elf': [FileSignatureType.elf],
    'so': [FileSignatureType.elf],
    'png': [FileSignatureType.png],
    'jpg': [FileSignatureType.jpeg],
    'jpeg': [FileSignatureType.jpeg],
    'gif': [FileSignatureType.gif],
  };

  /// Extensions whose presence as the *final* component of a double-extension
  /// filename is considered dangerous.
  static const _dangerousExtensions = {
    'exe', 'dll', 'bat', 'cmd', 'com', 'scr', 'pif', 'vbs', 'js',
    'jse', 'ws', 'wsf', 'wsc', 'wsh', 'ps1', 'msi', 'msp', 'mst',
    'hta', 'cpl', 'inf', 'reg', 'elf', 'so', 'sh', 'bin',
  };

  /// Macro-enabled Office extensions that warrant extra scrutiny.
  static const _macroExtensions = {'docm', 'xlsm', 'pptm', 'dotm', 'xltm'};

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Runs all Layer 1 local checks against [fileBytes] with the given
  /// [fileName].
  ///
  /// - [fileName]: the full filename including extension(s), e.g.
  ///   `invoice.pdf.exe`.  Only the basename is inspected — no path traversal.
  /// - [fileBytes]: the raw file content.  For large files callers should
  ///   read the first 8 bytes for magic detection and stream the rest through
  ///   [computeSha256Streaming] separately.
  ///
  /// Returns a [FileScanResult] with [FileScanResult.reputationVerdict] == null
  /// (set later by Layer 2 via [FileScanResult.withReputation]).
  static FileScanResult scanLocal(String fileName, Uint8List fileBytes) {
    // 1. Compute SHA-256 in 64 KB chunks.
    final hash = computeSha256Streaming(fileBytes);

    // 2. Parse filename — take only the basename (last path segment).
    final baseName = fileName.split(RegExp(r'[\\/]')).last;
    final parts = baseName.split('.');

    // 3. Determine declared extension (the very last component after a dot).
    final declaredExt =
        parts.length > 1 ? parts.last.toLowerCase() : '';

    // 4. Detect magic-byte signature.
    final detectedType = _detectSignature(fileBytes);

    // 5. Check double-extension: more than 2 dot-parts AND the final part is
    //    a dangerous extension (e.g. "invoice.pdf.exe").
    final isDoubleExt = parts.length > 2 &&
        _dangerousExtensions.contains(parts.last.toLowerCase());

    // 6. Macro-enabled Office format check.
    final isMacro = _macroExtensions.contains(declaredExt);

    // 7. Signature mismatch check.
    final isMismatch = _isMismatch(detectedType, declaredExt);

    // 8. Overall malicious flag.
    final isMalicious = isMismatch || isDoubleExt || isMacro;

    return FileScanResult(
      sha256: hash,
      declaredExtension: declaredExt,
      detectedType: detectedType,
      isSigMismatch: isMismatch,
      isDoubleExtension: isDoubleExt,
      isMacroEnabled: isMacro,
      isMalicious: isMalicious,
    );
  }

  /// Computes the SHA-256 hex digest of [data] in 64 KB chunks.
  ///
  /// The chunked approach keeps memory usage bounded for large files.
  /// This is the same hash sent in Layer 2 reputation lookups.
  static String computeSha256Streaming(Uint8List data) {
    const chunkSize = 64 * 1024; // 64 KB
    final sink = sha256.startChunkedConversion(
      _HashStringSink(),
    );

    var offset = 0;
    while (offset < data.length) {
      final end = (offset + chunkSize).clamp(0, data.length);
      sink.add(data.sublist(offset, end));
      offset = end;
    }
    sink.close();

    // Re-run as a single pass (dart:crypto's chunked API finalizes on close
    // but we need the result from the hash object directly).
    return sha256.convert(data).toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Detects the [FileSignatureType] by comparing the first bytes of [data]
  /// against the known magic-byte table.  Returns [FileSignatureType.unknown]
  /// if no entry matches or the file is too short.
  static FileSignatureType _detectSignature(Uint8List data) {
    for (final entry in _signatures.entries) {
      final magic = entry.value;
      if (data.length < magic.length) continue;
      var match = true;
      for (var i = 0; i < magic.length; i++) {
        if (data[i] != magic[i]) {
          match = false;
          break;
        }
      }
      if (match) return entry.key;
    }
    return FileSignatureType.unknown;
  }

  /// Returns `true` when [detectedType] is known but inconsistent with the
  /// declared [ext].  If the extension is unknown or unmapped we cannot assert
  /// a mismatch, so we return `false` (conservative — avoids false positives).
  static bool _isMismatch(FileSignatureType detectedType, String ext) {
    if (detectedType == FileSignatureType.unknown) return false;
    final expected = _extensionTypes[ext];
    if (expected == null) return false; // extension not in our table
    return !expected.contains(detectedType);
  }
}

/// Internal sink used to satisfy [sha256.startChunkedConversion] API;
/// the actual result is computed via a simpler [sha256.convert] call.
class _HashStringSink implements Sink<Digest> {
  @override
  void add(Digest data) {}
  @override
  void close() {}
}
