import 'dart:typed_data';
import 'native_crypto_bridge.dart';

/// Stub implementation of [NativeCryptoBridge].
class NativeCryptoBridgeImpl implements NativeCryptoBridge {
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
}
