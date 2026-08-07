import 'package:flutter/services.dart';

/// Dart service communicating with iOS AutoFill Credential Provider Extension via MethodChannel.
class IosPasskeyService {
  static const MethodChannel _channel = MethodChannel('com.example.app/passkeys_ios');

  final MethodChannel channel;

  IosPasskeyService({MethodChannel? channelOverride})
      : channel = channelOverride ?? _channel;

  /// Checks if current iOS system supports AutoFill Passkey extensions (iOS 17+).
  Future<bool> isPasskeyExtensionSupported() async {
    try {
      final bool? supported = await channel.invokeMethod<bool>('isPasskeyExtensionSupported');
      return supported ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Syncs an encrypted passkey payload to the shared iOS App Group container (`group.io.sentinelvault.app`).
  Future<bool> syncPasskeyToAppGroup(String jsonPayload) async {
    try {
      final bool? success = await channel.invokeMethod<bool>(
        'syncPasskeyToAppGroup',
        {'payload': jsonPayload},
      );
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }
}
