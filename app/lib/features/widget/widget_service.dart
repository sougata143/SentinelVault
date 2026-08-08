import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:core/core.dart';

/// Manages home-screen widget data synchronization and security lock-state purging.
///
/// Security Invariants:
/// 1. Shared widget storage holds ONLY transient data for items where `isAvailableInWidget == true`.
/// 2. When the vault locks or logs out, shared widget storage is immediately purged and set to `lockState: locked`.
/// 3. In-app lock, auto-lock timeout, and duress unlock triggers immediately sanitize shared widget storage.
class WidgetService {
  static const String appGroupId = 'group.com.sentinelvault.app';
  static const String androidWidgetName = 'SentinelVaultWidgetProvider';
  static const String iOSWidgetName = 'SentinelVaultWidget';
  static const String widgetDataKey = 'sentinelvault_widget_data';

  static final WidgetService instance = WidgetService._internal();

  NativeCryptoBridge _cryptoBridge;

  WidgetService._internal({NativeCryptoBridge? bridge})
      : _cryptoBridge = bridge ?? getNativeCryptoBridge();

  /// Inject custom crypto bridge (for testing).
  void setCryptoBridge(NativeCryptoBridge bridge) {
    _cryptoBridge = bridge;
  }

  /// Initializes App Group ID for iOS home_widget storage.
  Future<void> init() async {
    try {
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
        await HomeWidget.setAppGroupId(appGroupId);
      }
    } catch (e) {
      debugPrint('WidgetService init error: $e');
    }
  }

  /// Updates shared widget data with active TOTP codes for opt-in items when unlocked.
  /// If [isLocked] is true or [items] is empty/locked, calls [purgeWidgetData].
  Future<Map<String, dynamic>> updateWidgetData({
    required List<VaultItem> items,
    required bool isLocked,
  }) async {
    if (isLocked) {
      return purgeWidgetData();
    }

    final optInItems = items.where((item) => item.isAvailableInWidget && item.hasTotpSecret).toList();

    if (optInItems.isEmpty) {
      return purgeWidgetData(keepUnlockedEmptyState: true);
    }

    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final List<Map<String, dynamic>> itemPayloads = [];

    for (final item in optInItems) {
      final secret = item.totpSecret;
      if (secret == null || secret.isEmpty) continue;

      String code = '------';
      int period = 30;
      int digits = 6;
      String algorithm = 'SHA1';
      String issuer = item.title;
      String account = '';

      if (item.fields is TotpFields) {
        final f = item.fields as TotpFields;
        period = f.period;
        digits = f.digits;
        algorithm = f.algorithm;
        if (f.issuer.isNotEmpty) issuer = f.issuer;
        account = f.accountName;
      } else if (item.fields is LoginFields) {
        final f = item.fields as LoginFields;
        account = f.username;
      }

      try {
        code = await _cryptoBridge.generateTotpCode(
          secret: secret,
          timestampSec: nowSec,
          period: period,
          digits: digits,
          algorithm: algorithm,
        );
      } catch (_) {
        code = TotpHelper.generateTotpCode(
          secret: secret,
          timestampSec: nowSec,
          period: period,
          digits: digits,
          algorithm: algorithm,
        );
      }

      itemPayloads.add({
        'id': item.id,
        'title': item.title,
        'issuer': issuer,
        'account': account,
        'code': code,
        'period': period,
        'digits': digits,
        'updatedAtSec': nowSec,
      });
    }

    final payload = {
      'lockState': 'unlocked',
      'items': itemPayloads,
    };

    final jsonString = jsonEncode(payload);

    try {
      if (!kIsWeb) {
        await HomeWidget.saveWidgetData<String>(widgetDataKey, jsonString);
        await HomeWidget.updateWidget(
          name: androidWidgetName,
          iOSName: iOSWidgetName,
        );
      }
    } catch (e) {
      debugPrint('WidgetService update error: $e');
    }

    return payload;
  }

  /// Immediately sanitizes shared widget storage and notifies home widgets to show locked state.
  Future<Map<String, dynamic>> purgeWidgetData({bool keepUnlockedEmptyState = false}) async {
    final payload = {
      'lockState': keepUnlockedEmptyState ? 'unlocked' : 'locked',
      'items': <Map<String, dynamic>>[],
    };

    final jsonString = jsonEncode(payload);

    try {
      if (!kIsWeb) {
        await HomeWidget.saveWidgetData<String>(widgetDataKey, jsonString);
        await HomeWidget.updateWidget(
          name: androidWidgetName,
          iOSName: iOSWidgetName,
        );
      }
    } catch (e) {
      debugPrint('WidgetService purge error: $e');
    }

    return payload;
  }
}
