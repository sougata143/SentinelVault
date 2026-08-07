import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:core/core.dart';

/// Dart service communicating with Android CredentialManager CredentialProviderService via MethodChannel.
class AndroidPasskeyService {
  static const MethodChannel _channel = MethodChannel('com.example.app/passkeys');

  final MethodChannel channel;

  AndroidPasskeyService({MethodChannel? channelOverride})
      : channel = channelOverride ?? _channel;

  /// Checks if the current OS supports Android 14+ Credential Provider framework.
  Future<bool> isPasskeyProviderSupported() async {
    try {
      final bool? supported = await channel.invokeMethod<bool>('isPasskeyProviderSupported');
      return supported ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Fetches pending Android CredentialManager intent payload if app was launched via CredentialProviderService.
  Future<Map<String, dynamic>?> getPendingPasskeyIntent() async {
    try {
      final Map<dynamic, dynamic>? res = await channel.invokeMethod('getPendingPasskeyIntent');
      if (res == null) return null;
      return Map<String, dynamic>.from(res);
    } on PlatformException {
      return null;
    }
  }

  /// Parses WebAuthn creation/registration parameters from JSON.
  Map<String, dynamic> parseRegistrationRequest(String requestJson) {
    if (requestJson.isEmpty) return {};
    try {
      final map = jsonDecode(requestJson) as Map<String, dynamic>;
      final rp = map['rp'] as Map<String, dynamic>? ?? {};
      final user = map['user'] as Map<String, dynamic>? ?? {};
      return {
        'rpId': rp['id'] as String? ?? '',
        'rpName': rp['name'] as String? ?? '',
        'userName': user['name'] as String? ?? user['displayName'] as String? ?? '',
        'userHandle': user['id'] as String? ?? '',
        'challenge': map['challenge'] as String? ?? '',
      };
    } catch (_) {
      return {};
    }
  }

  /// Creates a new [PasskeyVaultItem] from an Android CredentialManager registration request.
  PasskeyVaultItem createPasskeyFromRequest({
    required String rpId,
    required String userName,
    required String userHandle,
    required String privateKeyPem,
    required String publicKeyRaw,
    required String cosePublicKey,
  }) {
    final credId = 'android_cred_${DateTime.now().millisecondsSinceEpoch}_${rpId.replaceAll('.', '_')}';
    return PasskeyVaultItem(
      rpId: rpId,
      userHandle: userHandle,
      userName: userName,
      credentialId: credId,
      privateKeyPem: ConcealedValue.plain(privateKeyPem),
      publicKeyRaw: publicKeyRaw,
      cosePublicKey: cosePublicKey,
      signCount: 0,
      createdAt: DateTime.now().toUtc(),
    );
  }
}
