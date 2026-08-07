import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app/features/settings/manage_devices_screen.dart';

void main() {
  testWidgets('ManageDevicesScreen displays session list and badges current session', (widgetTester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/sessions') && request.method == 'GET') {
        return http.Response(
          json.encode([
            {
              'id': 'sess-1',
              'deviceLabel': 'Chrome on Windows',
              'loginMethod': 'password',
              'createdAt': '2026-08-08T04:00:00.000Z',
              'lastActiveAt': '2026-08-08T04:30:00.000Z',
              'isCurrent': true,
            },
            {
              'id': 'sess-2',
              'deviceLabel': 'SentinelVault iOS App',
              'loginMethod': 'passkey',
              'createdAt': '2026-08-07T12:00:00.000Z',
              'lastActiveAt': '2026-08-07T15:00:00.000Z',
              'isCurrent': false,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not Found', 444);
    });

    await widgetTester.pumpWidget(
      MaterialApp(
        home: ManageDevicesScreen(
          authBaseUrl: 'http://localhost:3001',
          jwtToken: 'mock_jwt_token',
          httpClient: mockClient,
        ),
      ),
    );

    // Initial pump shows loading or fetches data
    await widgetTester.pumpAndSettle();

    expect(find.text('Manage Devices & Sessions'), findsOneWidget);
    expect(find.text('Chrome on Windows'), findsOneWidget);
    expect(find.text('SentinelVault iOS App'), findsOneWidget);
    expect(find.text('This Device'), findsOneWidget);
    expect(find.byKey(const Key('revoke-btn-sess-2')), findsOneWidget);
  });

  testWidgets('Revoking a session triggers delete request and shows confirmation', (widgetTester) async {
    bool deleteCalled = false;
    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/sessions') && request.method == 'GET') {
        return http.Response(
          json.encode([
            {
              'id': 'sess-1',
              'deviceLabel': 'Chrome on Windows',
              'loginMethod': 'password',
              'createdAt': '2026-08-08T04:00:00.000Z',
              'lastActiveAt': '2026-08-08T04:30:00.000Z',
              'isCurrent': true,
            },
            {
              'id': 'sess-2',
              'deviceLabel': 'Firefox on Linux',
              'loginMethod': 'password',
              'createdAt': '2026-08-07T12:00:00.000Z',
              'lastActiveAt': '2026-08-07T15:00:00.000Z',
              'isCurrent': false,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      } else if (request.url.path.endsWith('/auth/sessions/sess-2') && request.method == 'DELETE') {
        deleteCalled = true;
        return http.Response(json.encode({'success': true}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('Not Found', 444);
    });

    await widgetTester.pumpWidget(
      MaterialApp(
        home: ManageDevicesScreen(
          authBaseUrl: 'http://localhost:3001',
          jwtToken: 'mock_jwt_token',
          httpClient: mockClient,
        ),
      ),
    );

    await widgetTester.pumpAndSettle();

    final revokeBtn = find.byKey(const Key('revoke-btn-sess-2'));
    expect(revokeBtn, findsOneWidget);

    await widgetTester.tap(revokeBtn);
    await widgetTester.pumpAndSettle();

    // Confirmation dialog should be visible
    expect(find.text('Revoke Session'), findsOneWidget);
    expect(find.text('Are you sure you want to revoke access for "Firefox on Linux"? The device will be logged out immediately.'), findsOneWidget);

    // Tap confirm Revoke button in dialog
    final dialogRevokeBtn = find.byKey(const Key('confirm-revoke-dialog-btn'));
    await widgetTester.tap(dialogRevokeBtn);
    await widgetTester.pumpAndSettle();

    expect(deleteCalled, isTrue);
  });
}
