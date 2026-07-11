import 'dart:js_interop';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;

import 'native_crypto_bridge.dart';

// --- JS Bindings ---

@JS()
external JSUint8Array wasmDeriveMasterKey(JSUint8Array password, JSUint8Array salt);

@JS()
external JSUint8Array wasmEncryptAesGcm(JSUint8Array key, JSUint8Array nonce, JSUint8Array plaintext);

@JS()
external JSUint8Array wasmDecryptAesGcm(JSUint8Array key, JSUint8Array nonce, JSUint8Array ciphertext);

@JS()
external JSUint8Array wasmSrpCalculateX(JSString username, JSUint8Array masterKey, JSUint8Array salt);

@JS()
external JSUint8Array wasmSrpCalculateVerifier(JSString username, JSUint8Array masterKey, JSUint8Array salt);

@JS()
external JSUint8Array wasmSrpGenerateClientEphemeral(JSUint8Array aBytes);

@JS()
external JSUint8Array wasmSrpCalculateClientSession(
  JSString username,
  JSUint8Array salt,
  JSUint8Array aBytes,
  JSUint8Array aPubBytes,
  JSUint8Array bPubBytes,
  JSUint8Array masterKey,
);

@JS()
external JSUint8Array wasmShamirSplit(JSUint8Array secret, JSNumber m, JSNumber n);

@JS()
external JSUint8Array wasmShamirCombine(JSUint8Array flatShares);

class NativeCryptoBridgeImpl implements NativeCryptoBridge {
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
  Future<PqcKeyBundle> pqcGenerateKeypairs() => throw UnimplementedError();

  @override
  Future<PqcWrappedKey> pqcHybridWrap({
    required Uint8List recipientX25519Pub,
    required Uint8List recipientMlkemEk,
    required Uint8List folderKey,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> pqcHybridUnwrap({
    required Uint8List recipientX25519Priv,
    required Uint8List recipientMlkemDk,
    required PqcWrappedKey wrappedKey,
  }) => throw UnimplementedError();

  @override
  Future<PqcSignatureBundle> pqcSignInvitation({
    required Uint8List payload,
    required Uint8List ed25519Priv,
    required Uint8List mldsaSeed,
  }) => throw UnimplementedError();

  @override
  Future<bool> pqcVerifyInvitation({
    required Uint8List payload,
    required Uint8List ed25519Pub,
    required Uint8List mldsaVk,
    required PqcSignatureBundle signatures,
  }) => throw UnimplementedError();
}
