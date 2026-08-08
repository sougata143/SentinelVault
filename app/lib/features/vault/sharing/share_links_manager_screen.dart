import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../theme/theme.dart';
import '../../../config/api_config.dart';

class ShareLinkOwnerRecord {
  final String shareId;
  final String? itemTitle;
  final DateTime expiresAt;
  final bool oneTimeView;
  final int viewCount;
  final bool isConsumed;
  final bool isRevoked;
  final DateTime createdAt;

  const ShareLinkOwnerRecord({
    required this.shareId,
    this.itemTitle,
    required this.expiresAt,
    required this.oneTimeView,
    required this.viewCount,
    required this.isConsumed,
    required this.isRevoked,
    required this.createdAt,
  });

  factory ShareLinkOwnerRecord.fromJson(Map<String, dynamic> json) {
    return ShareLinkOwnerRecord(
      shareId: json['shareId'] as String,
      itemTitle: json['itemTitle'] as String?,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      oneTimeView: json['oneTimeView'] as bool? ?? true,
      viewCount: json['viewCount'] as int? ?? 0,
      isConsumed: json['isConsumed'] as bool? ?? false,
      isRevoked: json['isRevoked'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class ShareLinksManagerScreen extends StatefulWidget {
  final String sharingBaseUrl;
  final String? sessionToken;
  final http.Client? httpClient;

  const ShareLinksManagerScreen({
    super.key,
    required this.sharingBaseUrl,
    this.sessionToken,
    this.httpClient,
  });

  @override
  State<ShareLinksManagerScreen> createState() => _ShareLinksManagerScreenState();
}

class _ShareLinksManagerScreenState extends State<ShareLinksManagerScreen> {
  List<ShareLinkOwnerRecord> _links = [];
  bool _isLoading = true;
  String? _errorMessage;

  String get _effectiveSharingBaseUrl =>
      widget.sharingBaseUrl.isNotEmpty ? widget.sharingBaseUrl : ApiConfig.sharingBaseUrl;

  @override
  void initState() {
    super.initState();
    _fetchLinks();
  }

  Future<void> _fetchLinks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = widget.httpClient ?? http.Client();
      final uri = Uri.parse('$_effectiveSharingBaseUrl/share-links/my-links/all');

      final response = await client.get(
        uri,
        headers: {
          if (widget.sessionToken != null) 'Authorization': 'Bearer ${widget.sessionToken}',
        },
      );

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        setState(() {
          _links = list.map((e) => ShareLinkOwnerRecord.fromJson(e)).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load share links (HTTP ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading share links: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _revokeLink(String shareId) async {
    try {
      final client = widget.httpClient ?? http.Client();
      final uri = Uri.parse('$_effectiveSharingBaseUrl/share-links/$shareId/revoke');

      final response = await client.post(
        uri,
        headers: {
          if (widget.sessionToken != null) 'Authorization': 'Bearer ${widget.sessionToken}',
        },
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share link revoked successfully.')),
        );
        _fetchLinks();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error revoking link: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SentinelTheme.backgroundDark,
      appBar: AppBar(
        title: const Text('Active Secure Share Links'),
        backgroundColor: SentinelTheme.surfaceDark,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: SentinelTheme.accentCyan))
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
              : _links.isEmpty
                  ? const Center(
                      child: Text(
                        'No active share links found.',
                        style: TextStyle(color: SentinelTheme.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _links.length,
                      itemBuilder: (context, index) {
                        final link = _links[index];
                        final isExpired = DateTime.now().isAfter(link.expiresAt);

                        String statusText = 'Active';
                        Color statusColor = SentinelTheme.accentCyan;

                        if (link.isRevoked) {
                          statusText = 'Revoked';
                          statusColor = Colors.redAccent;
                        } else if (link.isConsumed) {
                          statusText = 'Consumed';
                          statusColor = SentinelTheme.textMuted;
                        } else if (isExpired) {
                          statusText = 'Expired';
                          statusColor = SentinelTheme.warningYellow;
                        }

                        return Card(
                          color: SentinelTheme.cardDark,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: SentinelTheme.borderDark),
                          ),
                          child: ListTile(
                            title: Text(
                              link.itemTitle ?? 'Untitled Item',
                              style: const TextStyle(
                                color: SentinelTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Expires: ${link.expiresAt.toLocal()}',
                                  style: const TextStyle(color: SentinelTheme.textMuted, fontSize: 12),
                                ),
                                Text(
                                  'Type: ${link.oneTimeView ? "One-Time View" : "Multi-View"} | Views: ${link.viewCount}',
                                  style: const TextStyle(color: SentinelTheme.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                  backgroundColor: statusColor.withValues(alpha: 0.12),
                                  side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
                                ),
                                if (!link.isRevoked && !link.isConsumed && !isExpired)
                                  IconButton(
                                    icon: const Icon(Icons.block, color: Colors.redAccent, size: 20),
                                    tooltip: 'Revoke Link',
                                    onPressed: () => _revokeLink(link.shareId),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
