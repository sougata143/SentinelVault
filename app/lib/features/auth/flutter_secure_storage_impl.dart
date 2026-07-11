import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:core/core.dart';

/// Flutter implementation of [SecureStorage] using `flutter_secure_storage` 
/// for session tokens and a native platform MethodChannel for the hardware key.
class FlutterPlatformSecureStorage implements SecureStorage {
  final _secureStorage = const FlutterSecureStorage();
  static const _channel = MethodChannel('com.example.app/secure_storage');

  static const _sessionTokenKey = 'session_token';

  @override
  Future<void> writeSessionToken(String token) async {
    await _secureStorage.write(
      key: _sessionTokenKey, 
      value: token,
      // For general session tokens, use standard secure at rest options
      iOptions: const IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      aOptions: const AndroidOptions(encryptedSharedPreferences: false),
    );
  }

  @override
  Future<String?> readSessionToken() async {
    return await _secureStorage.read(key: _sessionTokenKey);
  }

  @override
  Future<void> deleteSessionToken() async {
    await _secureStorage.delete(key: _sessionTokenKey);
  }

  @override
  Future<bool> isHardwareKeySupported() async {
    try {
      final bool? supported = await _channel.invokeMethod<bool>('isHardwareSecureSupported');
      return supported ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> writeBiometricWrappedVaultKey(List<int> masterKey, List<int> vaultKey) async {
    final combined = Uint8List(64);
    combined.setRange(0, 32, masterKey);
    combined.setRange(32, 64, vaultKey);

    await _channel.invokeMethod('writeBiometricWrappedVaultKey', {
      'payload': combined,
    });
  }

  @override
  Future<Map<String, List<int>>?> readBiometricWrappedVaultKey() async {
    try {
      final Uint8List? result = await _channel.invokeMethod<Uint8List>('readBiometricWrappedVaultKey');
      if (result == null || result.length != 64) {
        return null;
      }
      final masterKey = result.sublist(0, 32);
      final vaultKey = result.sublist(32, 64);
      return {
        'masterKey': masterKey,
        'vaultKey': vaultKey,
      };
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> deleteBiometricWrappedVaultKey() async {
    try {
      await _channel.invokeMethod('deleteBiometricWrappedVaultKey');
    } catch (e) {
      // ignore errors on deletion
    }
  }

  @override
  Future<bool> wasEnrollmentChanged() async {
    try {
      final bool? changed = await _channel.invokeMethod<bool>('wasEnrollmentChanged');
      return changed ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> resetEnrollmentStatus() async {
    try {
      await _channel.invokeMethod('resetEnrollmentStatus');
    } catch (e) {
      // ignore
    }
  }
}
