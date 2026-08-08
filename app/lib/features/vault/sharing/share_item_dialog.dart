import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import '../../../theme/theme.dart';
import '../../../config/api_config.dart';

/// Modal dialog for generating zero-knowledge secure share links for an item.
class ShareItemDialog extends StatefulWidget {
  final VaultItem item;
  final String sharingBaseUrl;
  final String? sessionToken;
  final http.Client? httpClient;

  const ShareItemDialog({
    super.key,
    required this.item,
    required this.sharingBaseUrl,
    this.sessionToken,
    this.httpClient,
  });

  @override
  State<ShareItemDialog> createState() => _ShareItemDialogState();
}

class _ShareItemDialogState extends State<ShareItemDialog> {
  int _selectedExpiryHours = 24;
  bool _oneTimeView = true;
  bool _isGenerating = false;
  String? _generatedUrl;
  String? _errorMessage;

  String get _effectiveSharingBaseUrl =>
      widget.sharingBaseUrl.isNotEmpty ? widget.sharingBaseUrl : ApiConfig.sharingBaseUrl;

  Future<void> _generateShareLink() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final crypto = VaultCrypto();
      final itemJson = jsonEncode(widget.item.toJson());

      // 1. Client-side ephemeral key generation & AES-GCM encryption
      final encResult = await SecureShareHelper.encryptSharePayload(
        jsonPayload: itemJson,
        crypto: crypto,
      );

      // 2. Post ONLY ciphertext & metadata to server
      final client = widget.httpClient ?? http.Client();
      final uri = Uri.parse('$_effectiveSharingBaseUrl/sharing/share-links');

      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (widget.sessionToken != null) 'Authorization': 'Bearer ${widget.sessionToken}',
        },
        body: jsonEncode({
          'encryptedBlob': encResult.encryptedBlob,
          'nonce': encResult.nonce,
          'itemTitle': widget.item.title,
          'expiryHours': _selectedExpiryHours,
          'oneTimeView': _oneTimeView,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        final shareId = resJson['shareId'] as String;

        // 3. Construct share link with decryption key ONLY in the # fragment
        final fullUrl = SecureShareHelper.buildShareUrl(
          baseUrl: 'https://sentinelvault.app',
          shareId: shareId,
          shareKeyHex: encResult.shareKeyHex,
        );

        setState(() {
          _generatedUrl = fullUrl;
          _isGenerating = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to create share link (HTTP ${response.statusCode})';
          _isGenerating = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error generating share link: $e';
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SentinelTheme.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.share_outlined, color: SentinelTheme.accentCyan),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Share "${widget.item.title}"',
              style: const TextStyle(color: SentinelTheme.textPrimary, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning Notice Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SentinelTheme.warningYellow.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SentinelTheme.warningYellow.withValues(alpha: 0.5)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: SentinelTheme.warningYellow, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Anyone with this link can view this item\'s contents. The decryption key travels strictly in the URL fragment (#) and is never sent to our servers.',
                      style: TextStyle(color: SentinelTheme.textPrimary, fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_generatedUrl == null) ...[
              const Text(
                'Link Expiration',
                style: TextStyle(color: SentinelTheme.textMuted, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
              initialValue: _selectedExpiryHours,
                dropdownColor: SentinelTheme.cardDark,
                style: const TextStyle(color: SentinelTheme.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: SentinelTheme.cardDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 Hour')),
                  DropdownMenuItem(value: 12, child: Text('12 Hours')),
                  DropdownMenuItem(value: 24, child: Text('24 Hours (Default)')),
                  DropdownMenuItem(value: 72, child: Text('3 Days')),
                  DropdownMenuItem(value: 168, child: Text('7 Days')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedExpiryHours = val);
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: SentinelTheme.accentCyan,
                title: const Text(
                  'One-Time View',
                  style: TextStyle(color: SentinelTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Link expires and destroys contents immediately after recipient opens it once.',
                  style: TextStyle(color: SentinelTheme.textMuted, fontSize: 12),
                ),
                value: _oneTimeView,
                onChanged: (val) => setState(() => _oneTimeView = val),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ] else ...[
              const Text(
                'Your Secure Share Link is Ready:',
                style: TextStyle(color: SentinelTheme.accentCyan, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SentinelTheme.cardDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SentinelTheme.borderDark),
                ),
                child: SelectableText(
                  _generatedUrl!,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _generatedUrl!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Share link copied to clipboard!')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy Share Link'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SentinelTheme.accentCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_generatedUrl == null ? 'Cancel' : 'Close', style: const TextStyle(color: SentinelTheme.textMuted)),
        ),
        if (_generatedUrl == null)
          ElevatedButton(
            onPressed: _isGenerating ? null : _generateShareLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: SentinelTheme.accentCyan,
              foregroundColor: Colors.black,
            ),
            child: _isGenerating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Generate Link'),
          ),
      ],
    );
  }
}
