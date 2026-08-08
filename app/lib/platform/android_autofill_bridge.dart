import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:core/core.dart';

/// Platform channel bridge interfacing with Android system-wide Autofill Framework.
class AndroidAutofillBridge {
  static const MethodChannel _channel = MethodChannel('com.example.app/autofill');

  /// Checks if SentinelVault is currently set as the active Android System Autofill Service.
  static Future<bool> isAutofillServiceEnabled() async {
    try {
      final bool enabled = await _channel.invokeMethod('isAutofillServiceEnabled');
      return enabled;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android System Settings prompt requesting user to select SentinelVault as Autofill Provider.
  static Future<bool> requestSetAutofillService() async {
    try {
      final bool success = await _channel.invokeMethod('requestSetAutofillService');
      return success;
    } catch (_) {
      return false;
    }
  }

  /// Syncs unlocked vault items into encrypted local autofill cache for background service access.
  static Future<bool> syncVaultCredentialsForAutofill(List<VaultItem> items) async {
    try {
      final payloadList = items.map((item) {
        String username = '';
        String password = '';
        String uri = '';

        if (item.fields is LoginFields) {
          final lf = item.fields as LoginFields;
          username = lf.username;
          password = lf.password.plaintext ?? '';
          if (lf.urls.isNotEmpty) {
            uri = lf.urls.first;
          }
        }

        String domain = '';
        String packageName = '';

        if (uri.startsWith('android://')) {
          packageName = uri.replaceFirst('android://', '').trim();
        } else if (uri.isNotEmpty) {
          try {
            final parsed = Uri.parse(uri.contains('://') ? uri : 'https://$uri');
            domain = parsed.host;
          } catch (_) {
            domain = uri;
          }
        }

        return {
          'id': item.id,
          'title': item.title,
          'username': username,
          'password': password,
          'domain': domain,
          'package': packageName,
        };
      }).toList();

      final jsonStr = jsonEncode(payloadList);
      final bool success = await _channel.invokeMethod('syncVaultCredentialsForAutofill', {
        'credentialsJson': jsonStr,
      });
      return success;
    } catch (_) {
      return false;
    }
  }
}
