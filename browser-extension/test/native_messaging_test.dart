import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';

void main() {
  group('Native Messaging Integration Tests', () {
    Process? hostProcess;
    HttpServer? mockNativeAppServer;
    Stream<List<int>>? broadcastStdout;
    bool vaultLocked = false;
    List<Map<String, dynamic>> mockItems = [];

    setUpAll(() async {
      // 1. Start a mock native app HTTP server on port 16235
      mockNativeAppServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 16235);
      mockNativeAppServer!.listen((HttpRequest request) {
        request.response.headers.add('Content-Type', 'application/json');
        if (request.uri.path == '/status') {
          request.response.write(json.encode({
            'locked': vaultLocked,
            'unlocked': !vaultLocked,
          }));
        } else if (request.uri.path == '/items') {
          request.response.write(json.encode({
            'locked': vaultLocked,
            'items': vaultLocked ? [] : mockItems,
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        request.response.close();
      });

      hostProcess = await Process.start(
        'python3',
        ['-u', 'src/native-messaging/host.py'], // -u for unbuffered binary stdout/stdin
      );

      broadcastStdout = hostProcess!.stdout.asBroadcastStream();

      // Print stderr for debugging
      hostProcess!.stderr.transform(utf8.decoder).listen((error) {
        print('Host Process Stderr: $error');
      });
    });

    tearDownAll(() async {
      hostProcess?.kill();
      await mockNativeAppServer?.close();
    });

    // Helper to send a native message with 4-byte length prefix
    Future<void> sendNativeMessage(Map<String, dynamic> msg) async {
      final jsonStr = json.encode(msg);
      final bytes = utf8.encode(jsonStr);
      final lengthBytes = ByteData(4)..setUint32(0, bytes.length, Endian.host);
      hostProcess!.stdin.add(lengthBytes.buffer.asUint8List());
      hostProcess!.stdin.add(bytes);
      await hostProcess!.stdin.flush();
    }

    // Helper to read a native message response with 4-byte length prefix
    Future<Map<String, dynamic>> readNativeMessage() async {
      final completer = Completer<Map<String, dynamic>>();
      final accumulatedBytes = <int>[];
      StreamSubscription? sub;

      sub = broadcastStdout!.listen((data) {
        accumulatedBytes.addAll(data);
        if (accumulatedBytes.length >= 4) {
          final length = ByteData.sublistView(Uint8List.fromList(accumulatedBytes.sublist(0, 4)))
              .getUint32(0, Endian.host);
          if (accumulatedBytes.length >= 4 + length) {
            final msgBytes = accumulatedBytes.sublist(4, 4 + length);
            final msgStr = utf8.decode(msgBytes);
            completer.complete(json.decode(msgStr));
            sub?.cancel();
          }
        }
      }, onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      });

      return completer.future.timeout(const Duration(seconds: 4), onTimeout: () {
        sub?.cancel();
        throw TimeoutException('Timed out waiting for native messaging host response.');
      });
    }

    test('1. Host reports correct STATUS when unlocked', () async {
      vaultLocked = false;
      await sendNativeMessage({'type': 'STATUS'});
      final res = await readNativeMessage();
      expect(res['running'], isTrue);
      expect(res['locked'], isFalse);
      expect(res['unlocked'], isTrue);
    });

    test('2. Host reports locked STATUS when Lock is triggered in native app', () async {
      vaultLocked = true;
      await sendNativeMessage({'type': 'STATUS'});
      final res = await readNativeMessage();
      expect(res['running'], isTrue);
      expect(res['locked'], isTrue);
      expect(res['unlocked'], isFalse);
    });

    test('3. Host successfully retrieves matched items when unlocked', () async {
      vaultLocked = false;
      mockItems = [
        {'title': 'Google', 'username': 'user@gmail.com', 'password': 'pass123'}
      ];

      await sendNativeMessage({'type': 'GET_ITEMS', 'origin': 'https://google.com'});
      final res = await readNativeMessage();
      expect(res['success'], isTrue);
      expect(res['locked'], isFalse);
      expect(res['items'].length, equals(1));
      expect(res['items'][0]['username'], equals('user@gmail.com'));
    });

    test('4. Host returns empty list and locked flag when querying locked vault', () async {
      vaultLocked = true;
      await sendNativeMessage({'type': 'GET_ITEMS', 'origin': 'https://google.com'});
      final res = await readNativeMessage();
      expect(res['success'], isTrue);
      expect(res['locked'], isTrue);
      expect(res['items'], isEmpty);
    });
  });
}
