import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;

import 'native_crypto_bridge.dart';
import 'totp_helper.dart';

// --- JS Bindings ---

/// WebAssembly binding for generating TOTP codes.
@JS('wasm_generate_totp')
external JSString wasmGenerateTotp(
  JSString secret,
  JSNumber timestampSec,
  JSNumber period,
  JSNumber digits,
  JSString algorithm,
);

/// WebAssembly binding for master key derivation via Argon2id.
@JS()
external JSUint8Array wasmDeriveMasterKey(JSUint8Array password, JSUint8Array salt);

/// WebAssembly binding for AES-256-GCM encryption.
@JS()
external JSUint8Array wasmEncryptAesGcm(JSUint8Array key, JSUint8Array nonce, JSUint8Array plaintext);

/// WebAssembly binding for AES-256-GCM decryption.
@JS()
external JSUint8Array wasmDecryptAesGcm(JSUint8Array key, JSUint8Array nonce, JSUint8Array ciphertext);

/// WebAssembly binding for computing the SRP x parameter.
@JS()
external JSUint8Array wasmSrpCalculateX(JSString username, JSUint8Array masterKey, JSUint8Array salt);

/// WebAssembly binding for computing the SRP verifier.
@JS()
external JSUint8Array wasmSrpCalculateVerifier(JSString username, JSUint8Array masterKey, JSUint8Array salt);

/// WebAssembly binding for generating SRP client ephemeral values.
@JS()
external JSUint8Array wasmSrpGenerateClientEphemeral(JSUint8Array aBytes);

/// WebAssembly binding for computing the SRP client session evidence.
@JS()
external JSUint8Array wasmSrpCalculateClientSession(
  JSString username,
  JSUint8Array salt,
  JSUint8Array aBytes,
  JSUint8Array aPubBytes,
  JSUint8Array bPubBytes,
  JSUint8Array masterKey,
);

/// WebAssembly binding for Shamir's Secret Sharing split operation.
@JS()
external JSUint8Array wasmShamirSplit(JSUint8Array secret, JSNumber m, JSNumber n);

/// WebAssembly binding for Shamir's Secret Sharing combine operation.
@JS()
external JSUint8Array wasmShamirCombine(JSUint8Array flatShares);

/// WebAssembly binding for PQC generate keypairs.
@JS()
external JSUint8Array wasmPqcGenerateKeypairs();

/// WebAssembly binding for PQC hybrid wrap.
@JS()
external JSUint8Array wasmPqcHybridWrap(
  JSUint8Array recipientX25519Pub,
  JSUint8Array recipientMlkemEk,
  JSUint8Array folderKey,
);

/// WebAssembly binding for PQC hybrid unwrap.
@JS()
external JSUint8Array wasmPqcHybridUnwrap(
  JSUint8Array recipientX25519Priv,
  JSUint8Array recipientMlkemDk,
  JSUint8Array ephemX25519Pub,
  JSUint8Array mlkemCt,
  JSUint8Array aesNonce,
  JSUint8Array wrappedFk,
);

/// WebAssembly binding for PQC sign invitation.
@JS()
external JSUint8Array wasmPqcSignInvitation(
  JSUint8Array payload,
  JSUint8Array ed25519Priv,
  JSUint8Array mldsaSeed,
);

/// WebAssembly binding for PQC verify invitation.
@JS()
external JSBoolean wasmPqcVerifyInvitation(
  JSUint8Array payload,
  JSUint8Array ed25519Pub,
  JSUint8Array mldsaVk,
  JSUint8Array ed25519Sig,
  JSUint8Array mldsaSig,
);

/// JS binding for the Promise that resolves once the WASM crypto module is
/// fully initialised (set by the loader script in `app/web/index.html`).
@JS('__cryptoCoreReadyPromise')
external JSPromise? get _cryptoCoreReadyPromise;

/// A JS-interop-based implementation of [NativeCryptoBridge] for Web platforms.
///
/// Under the hood, this delegates to the compiled Rust `crypto_core` Wasm
/// library running inside the browser JS runtime context via wasm-bindgen.
///
/// **Security invariant:** No crypto function may be called before [ensureReady]
/// has completed.  Every method enforces this with [_checkReady]; callers that
/// skip [ensureReady] will receive a [StateError] rather than a silent
/// `NoSuchMethodError` from a missing JS global.
class NativeCryptoBridgeImpl implements NativeCryptoBridge {
  // ── WASM readiness ────────────────────────────────────────────────────────

  static bool _ready = false;
  static Completer<void>? _readyCompleter;

  /// Awaits the WASM module initialisation that the `index.html` loader script
  /// performs asynchronously at page load.
  ///
  /// Must be called once from `main()` (under a `kIsWeb` guard) **before**
  /// [runApp].  Subsequent calls return immediately once the module is ready.
  ///
  /// Throws if the WASM bundle failed to load (e.g. missing `pkg/crypto_core.js`).
  static Future<void> ensureReady() async {
    if (_ready) return;
    if (_readyCompleter != null) {
      return _readyCompleter!.future;
    }
    _readyCompleter = Completer<void>();
    try {
      final promise = _cryptoCoreReadyPromise;
      if (promise != null) {
        await promise.toDart;
      }
      _ready = true;
      _readyCompleter!.complete();
    } catch (e) {
      _readyCompleter!.completeError(
        Exception('Failed to initialise WASM crypto module: $e'),
      );
      rethrow;
    }
  }

  /// Throws [StateError] if [ensureReady] has not yet completed successfully.
  ///
  /// This gives a clear, actionable error instead of the opaque
  /// `NoSuchMethodError: tried to call a non-function, such as null` that
  /// would otherwise surface from a missing JS global.
  void _checkReady() {
    if (!_ready) {
      throw StateError(
        'WASM crypto module is not ready. '
        'Await NativeCryptoBridgeImpl.ensureReady() in main() before calling crypto functions.',
      );
    }
  }

  /// Creates a new [NativeCryptoBridgeImpl] instance for Web environments.
  NativeCryptoBridgeImpl();

  JSUint8Array _toJSArray(List<int> list) {
    final bytes = list is Uint8List ? list : Uint8List.fromList(list);
    return bytes.toJS;
  }

  Uint8List _toDartList(JSUint8Array jsArray) {
    return jsArray.toDart;
  }

  @override
  Future<Uint8List> deriveMasterKey({
    required List<int> password,
    required List<int> salt,
  }) async {
    _checkReady();
    try {
      final res = wasmDeriveMasterKey(_toJSArray(password), _toJSArray(salt));
      return _toDartList(res);
    } catch (e) {
      throw Exception('Wasm master key derivation failed: $e');
    }
  }

  @override
  Future<Uint8List> encryptAesGcm({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
  }) async {
    _checkReady();
    try {
      final res = wasmEncryptAesGcm(_toJSArray(key), _toJSArray(nonce), _toJSArray(plaintext));
      return _toDartList(res);
    } catch (e) {
      throw Exception('Wasm AES encrypt failed: $e');
    }
  }

  @override
  Future<Uint8List> decryptAesGcm({
    required List<int> ciphertextAndMac,
    required List<int> key,
    required List<int> nonce,
  }) async {
    _checkReady();
    try {
      final res = wasmDecryptAesGcm(_toJSArray(key), _toJSArray(nonce), _toJSArray(ciphertextAndMac));
      return _toDartList(res);
    } catch (e) {
      throw SecretBoxAuthenticationError();
    }
  }

  @override
  Future<Uint8List> srpCalculateX({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  }) async {
    _checkReady();
    try {
      final res = wasmSrpCalculateX(username.toJS, _toJSArray(masterKey), _toJSArray(salt));
      return _toDartList(res);
    } catch (e) {
      throw Exception('Wasm SRP calculate_x failed: $e');
    }
  }

  @override
  Future<Uint8List> srpCalculateVerifier({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  }) async {
    _checkReady();
    try {
      final res = wasmSrpCalculateVerifier(username.toJS, _toJSArray(masterKey), _toJSArray(salt));
      return _toDartList(res);
    } catch (e) {
      throw Exception('Wasm SRP calculate_verifier failed: $e');
    }
  }

  @override
  List<Uint8List> srpGenerateClientEphemeral({
    required List<int> secureRandomBytes,
  }) {
    _checkReady();
    try {
      final res = wasmSrpGenerateClientEphemeral(_toJSArray(secureRandomBytes));
      final dartBytes = _toDartList(res);
      final secret = Uint8List.sublistView(dartBytes, 0, 256);
      final publicVal = Uint8List.sublistView(dartBytes, 256, 512);
      return [secret, publicVal];
    } catch (e) {
      throw Exception('Wasm SRP generate_client_ephemeral failed: $e');
    }
  }

  @override
  Future<List<Uint8List>> srpCalculateClientSession({
    required String username,
    required List<int> salt,
    required List<int> a,
    required List<int> A,
    required List<int> B,
    required List<int> masterKey,
  }) async {
    _checkReady();
    try {
      final res = wasmSrpCalculateClientSession(
        username.toJS,
        _toJSArray(salt),
        _toJSArray(a),
        _toJSArray(A),
        _toJSArray(B),
        _toJSArray(masterKey),
      );
      final dartBytes = _toDartList(res);
      final sessionKey = Uint8List.sublistView(dartBytes, 0, 32);
      final clientEvidence = Uint8List.sublistView(dartBytes, 32, 64);
      final serverEvidence = Uint8List.sublistView(dartBytes, 64, 96);
      return [sessionKey, clientEvidence, serverEvidence];
    } catch (e) {
      throw Exception('Wasm SRP calculate_client_session failed: $e');
    }
  }

  @override
  List<Uint8List> shamirSplit({
    required Uint8List secret,
    required int m,
    required int n,
  }) {
    _checkReady();
    try {
      final res = wasmShamirSplit(_toJSArray(secret), m.toJS, n.toJS);
      final flatBytes = _toDartList(res);
      final shares = <Uint8List>[];
      var cursor = 0;
      while (cursor + 4 <= flatBytes.length) {
        final shareLen = flatBytes[cursor] |
            (flatBytes[cursor + 1] << 8) |
            (flatBytes[cursor + 2] << 16) |
            (flatBytes[cursor + 3] << 24);
        cursor += 4;
        if (cursor + shareLen > flatBytes.length) break;
        shares.add(Uint8List.fromList(flatBytes.sublist(cursor, cursor + shareLen)));
        cursor += shareLen;
      }
      if (shares.length != n) {
        throw StateError('wasm_shamir_split returned ${shares.length} shares, expected $n');
      }
      return shares;
    } catch (e) {
      throw ArgumentError('Wasm shamirSplit failed: $e');
    }
  }

  @override
  Uint8List shamirCombine({required List<Uint8List> shares}) {
    _checkReady();
    try {
      var flatLen = 0;
      for (final s in shares) {
        flatLen += 4 + s.length;
      }
      final flatBuf = Uint8List(flatLen);
      var cursor = 0;
      for (final s in shares) {
        final len = s.length;
        flatBuf[cursor] = len & 0xFF;
        flatBuf[cursor + 1] = (len >> 8) & 0xFF;
        flatBuf[cursor + 2] = (len >> 16) & 0xFF;
        flatBuf[cursor + 3] = (len >> 24) & 0xFF;
        cursor += 4;
        flatBuf.setRange(cursor, cursor + len, s);
        cursor += len;
      }
      final res = wasmShamirCombine(_toJSArray(flatBuf));
      return _toDartList(res);
    } catch (e) {
      throw ArgumentError('Wasm shamirCombine failed: $e — shares may be invalid or insufficient');
    }
  }

  @override
  Future<PqcKeyBundle> pqcGenerateKeypairs() async {
    _checkReady();
    try {
      final res = wasmPqcGenerateKeypairs();
      final buf = _toDartList(res);

      var cursor = 0;
      final x25519Pub = Uint8List.fromList(buf.sublist(cursor, cursor + 32)); cursor += 32;
      final x25519Priv = Uint8List.fromList(buf.sublist(cursor, cursor + 32)); cursor += 32;
      final ed25519Pub = Uint8List.fromList(buf.sublist(cursor, cursor + 32)); cursor += 32;
      final ed25519Priv = Uint8List.fromList(buf.sublist(cursor, cursor + 32)); cursor += 32;

      int readLen() {
        final len = buf[cursor] | (buf[cursor + 1] << 8) | (buf[cursor + 2] << 16) | (buf[cursor + 3] << 24);
        cursor += 4;
        return len;
      }

      final mlkemEkLen = readLen();
      final mlkemEk = Uint8List.fromList(buf.sublist(cursor, cursor + mlkemEkLen)); cursor += mlkemEkLen;

      final mlkemDkLen = readLen();
      final mlkemDk = Uint8List.fromList(buf.sublist(cursor, cursor + mlkemDkLen)); cursor += mlkemDkLen;

      final mldsaVkLen = readLen();
      final mldsaVk = Uint8List.fromList(buf.sublist(cursor, cursor + mldsaVkLen)); cursor += mldsaVkLen;

      final mldsaSeedLen = readLen();
      final mldsaSeed = Uint8List.fromList(buf.sublist(cursor, cursor + mldsaSeedLen)); cursor += mldsaSeedLen;

      return PqcKeyBundle(
        x25519Pub: x25519Pub,
        x25519Priv: x25519Priv,
        ed25519Pub: ed25519Pub,
        ed25519Priv: ed25519Priv,
        mlkemEk: mlkemEk,
        mlkemDk: mlkemDk,
        mldsaVk: mldsaVk,
        mldsaSeed: mldsaSeed,
      );
    } catch (e) {
      throw Exception('Wasm pqcGenerateKeypairs failed: $e');
    }
  }

  @override
  Future<PqcWrappedKey> pqcHybridWrap({
    required Uint8List recipientX25519Pub,
    required Uint8List recipientMlkemEk,
    required Uint8List folderKey,
  }) async {
    _checkReady();
    try {
      final res = wasmPqcHybridWrap(
        _toJSArray(recipientX25519Pub),
        _toJSArray(recipientMlkemEk),
        _toJSArray(folderKey),
      );
      final buf = _toDartList(res);

      var cursor = 0;
      final ephemPub = Uint8List.fromList(buf.sublist(cursor, cursor + 32)); cursor += 32;

      final kemCtLen = buf[cursor] | (buf[cursor + 1] << 8) | (buf[cursor + 2] << 16) | (buf[cursor + 3] << 24); cursor += 4;
      final kemCt = Uint8List.fromList(buf.sublist(cursor, cursor + kemCtLen)); cursor += kemCtLen;

      final nonce = Uint8List.fromList(buf.sublist(cursor, cursor + 12)); cursor += 12;

      final wrappedLen = buf[cursor] | (buf[cursor + 1] << 8) | (buf[cursor + 2] << 16) | (buf[cursor + 3] << 24); cursor += 4;
      final wrappedFk = Uint8List.fromList(buf.sublist(cursor, cursor + wrappedLen)); cursor += wrappedLen;

      return PqcWrappedKey(
        ephemeralX25519Pub: ephemPub,
        mlkemCiphertext: kemCt,
        aesNonce: nonce,
        wrappedFolderKey: wrappedFk,
      );
    } catch (e) {
      throw Exception('Wasm pqcHybridWrap failed: $e');
    }
  }

  @override
  Future<Uint8List> pqcHybridUnwrap({
    required Uint8List recipientX25519Priv,
    required Uint8List recipientMlkemDk,
    required PqcWrappedKey wrappedKey,
  }) async {
    _checkReady();
    try {
      final res = wasmPqcHybridUnwrap(
        _toJSArray(recipientX25519Priv),
        _toJSArray(recipientMlkemDk),
        _toJSArray(wrappedKey.ephemeralX25519Pub),
        _toJSArray(wrappedKey.mlkemCiphertext),
        _toJSArray(wrappedKey.aesNonce),
        _toJSArray(wrappedKey.wrappedFolderKey),
      );
      return _toDartList(res);
    } catch (e) {
      throw Exception('Wasm pqcHybridUnwrap failed: $e');
    }
  }

  @override
  Future<PqcSignatureBundle> pqcSignInvitation({
    required Uint8List payload,
    required Uint8List ed25519Priv,
    required Uint8List mldsaSeed,
  }) async {
    _checkReady();
    try {
      final res = wasmPqcSignInvitation(
        _toJSArray(payload),
        _toJSArray(ed25519Priv),
        _toJSArray(mldsaSeed),
      );
      final buf = _toDartList(res);

      var cursor = 0;
      final edLen = buf[cursor] | (buf[cursor + 1] << 8) | (buf[cursor + 2] << 16) | (buf[cursor + 3] << 24); cursor += 4;
      final edSig = Uint8List.fromList(buf.sublist(cursor, cursor + edLen)); cursor += edLen;

      final dsaLen = buf[cursor] | (buf[cursor + 1] << 8) | (buf[cursor + 2] << 16) | (buf[cursor + 3] << 24); cursor += 4;
      final dsaSig = Uint8List.fromList(buf.sublist(cursor, cursor + dsaLen)); cursor += dsaLen;

      return PqcSignatureBundle(
        ed25519Signature: edSig,
        mldsaSignature: dsaSig,
      );
    } catch (e) {
      throw Exception('Wasm pqcSignInvitation failed: $e');
    }
  }

  @override
  Future<bool> pqcVerifyInvitation({
    required Uint8List payload,
    required Uint8List ed25519Pub,
    required Uint8List mldsaVk,
    required PqcSignatureBundle signatures,
  }) async {
    _checkReady();
    try {
      final res = wasmPqcVerifyInvitation(
        _toJSArray(payload),
        _toJSArray(ed25519Pub),
        _toJSArray(mldsaVk),
        _toJSArray(signatures.ed25519Signature),
        _toJSArray(signatures.mldsaSignature),
      );
      return res.toDart;
    } catch (e) {
      throw Exception('Wasm pqcVerifyInvitation failed: $e');
    }
  }

  @override
  Future<String> generateTotpCode({
    required String secret,
    required int timestampSec,
    int period = 30,
    int digits = 6,
    String algorithm = 'SHA1',
  }) async {
    if (!_ready) {
      return TotpHelper.generateTotpCode(
        secret: secret,
        timestampSec: timestampSec,
        period: period,
        digits: digits,
        algorithm: algorithm,
      );
    }
    try {
      final res = wasmGenerateTotp(
        secret.toJS,
        timestampSec.toJS,
        period.toJS,
        digits.toJS,
        algorithm.toJS,
      );
      return res.toDart;
    } catch (_) {
      return TotpHelper.generateTotpCode(
        secret: secret,
        timestampSec: timestampSec,
        period: period,
        digits: digits,
        algorithm: algorithm,
      );
    }
  }
}
