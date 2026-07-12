import 'dart:typed_data';
import 'native_crypto_bridge.dart';

/// Stub implementation of [NativeCryptoBridge].
class NativeCryptoBridgeImpl implements NativeCryptoBridge {
  /// No-op on non-web platforms; the native FFI library is loaded
  /// synchronously and requires no async initialisation.
  static Future<void> ensureReady() async {}

  /// Creates a stub instance of [NativeCryptoBridgeImpl].
  ///
  /// Throws an [UnsupportedError] as this constructor should only be invoked
  /// in test environments or contexts without platform-specific implementations.
  NativeCryptoBridgeImpl() {
    throw UnsupportedError('Cannot create NativeCryptoBridge stub without platform-specific library');
  }

  @override
  Future<Uint8List> deriveMasterKey({
    required List<int> password,
    required List<int> salt,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> encryptAesGcm({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> decryptAesGcm({
    required List<int> ciphertextAndMac,
    required List<int> key,
    required List<int> nonce,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> srpCalculateX({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> srpCalculateVerifier({
    required String username,
    required List<int> masterKey,
    required List<int> salt,
  }) => throw UnimplementedError();

  @override
  List<Uint8List> srpGenerateClientEphemeral({
    required List<int> secureRandomBytes,
  }) => throw UnimplementedError();

  @override
  Future<List<Uint8List>> srpCalculateClientSession({
    required String username,
    required List<int> salt,
    required List<int> a,
    required List<int> A,
    required List<int> B,
    required List<int> masterKey,
  }) => throw UnimplementedError();

  @override
  List<Uint8List> shamirSplit({
    required Uint8List secret,
    required int m,
    required int n,
  }) => throw UnimplementedError();

  @override
  Uint8List shamirCombine({required List<Uint8List> shares}) =>
      throw UnimplementedError();

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
