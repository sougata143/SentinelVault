import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import '../../../theme/theme.dart';
import '../../../config/api_config.dart';

class RecipientShareViewScreen extends StatefulWidget {
  final String shareId;
  final String shareKeyHex;
  final String sharingBaseUrl;
  final http.Client? httpClient;

  const RecipientShareViewScreen({
    super.key,
    required this.shareId,
    required this.shareKeyHex,
    required this.sharingBaseUrl,
    this.httpClient,
  });

  @override
  State<RecipientShareViewScreen> createState() => _RecipientShareViewScreenState();
}

class _RecipientShareViewScreenState extends State<RecipientShareViewScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _decryptedItemJson;
  bool _isConsumed = false;

  String get _effectiveSharingBaseUrl =>
      widget.sharingBaseUrl.isNotEmpty ? widget.sharingBaseUrl : ApiConfig.sharingBaseUrl;

  @override
  void initState() {
    super.initState();
    _fetchAndDecryptShareLink();
  }

  Future<void> _fetchAndDecryptShareLink() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = widget.httpClient ?? http.Client();
      final uri = Uri.parse('$_effectiveSharingBaseUrl/sharing/share-links/${widget.shareId}');

      // Unauthenticated GET request to fetch ciphertext payload
      final response = await client.get(uri);

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        final encryptedBlob = resJson['encryptedBlob'] as String;
        final nonce = resJson['nonce'] as String;
        final oneTimeView = resJson['oneTimeView'] as bool? ?? true;

        // Client-side decryption using key from URL fragment
        final crypto = VaultCrypto();
        final decryptedJsonString = await SecureShareHelper.decryptSharePayload(
          encryptedBlobBase64: encryptedBlob,
          nonceBase64: nonce,
          shareKeyHex: widget.shareKeyHex,
          crypto: crypto,
        );

        final decodedMap = jsonDecode(decryptedJsonString) as Map<String, dynamic>;

        setState(() {
          _decryptedItemJson = decodedMap;
          _isConsumed = oneTimeView;
          _isLoading = false;
        });
      } else if (response.statusCode == 410) {
        setState(() {
          _errorMessage = '🔒 Share Link Expired or Consumed\nThis secure one-time link has already been viewed, expired, or revoked by the owner.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Unable to load share link (HTTP ${response.statusCode}).';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error decrypting share link. Please verify the link URL.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SentinelTheme.backgroundDark,
      appBar: AppBar(
        title: const Text('Secure Item Viewer'),
        backgroundColor: SentinelTheme.surfaceDark,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: SentinelTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SentinelTheme.borderDark),
            ),
            child: _isLoading
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: SentinelTheme.accentCyan),
                      SizedBox(height: 16),
                      Text('Decrypting shared payload client-side...', style: TextStyle(color: SentinelTheme.textMuted)),
                    ],
                  )
                : _errorMessage != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_clock_outlined, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 14, height: 1.4),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shield_outlined, color: SentinelTheme.accentCyan),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _decryptedItemJson?['title']?.toString() ?? 'Shared Credential',
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isConsumed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: SentinelTheme.accentCyan.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: SentinelTheme.accentCyan.withValues(alpha: 0.5)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.check_circle_outline, color: SentinelTheme.accentCyan, size: 16),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'One-Time View: This link is now consumed and destroyed on the server.',
                                      style: TextStyle(color: SentinelTheme.accentCyan, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          const Divider(color: SentinelTheme.borderDark),
                          const SizedBox(height: 12),
                          ..._buildFieldsList(_decryptedItemJson!),
                         ],
                      ),
            ),
          ), // end ConstrainedBox
        ),
      ),
    );
  }

  List<Widget> _buildFieldsList(Map<String, dynamic> itemJson) {
    final fields = <Widget>[];
    final innerFields = itemJson['fields'] as Map<String, dynamic>? ?? {};

    innerFields.forEach((key, val) {
      if (val != null) {
        String displayVal = val.toString();
        if (val is Map && val.containsKey('plaintext')) {
          displayVal = val['plaintext'].toString();
        }

        if (displayVal.isNotEmpty) {
          fields.add(
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SentinelTheme.surfaceDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(key.toUpperCase(), style: const TextStyle(color: SentinelTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(displayVal, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: SentinelTheme.accentCyan, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: displayVal));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied $key to clipboard!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }
      }
    });

    return fields;
  }
}
