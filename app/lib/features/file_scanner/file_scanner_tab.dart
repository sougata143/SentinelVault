import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:core/core.dart';

/// Full three-layer file security scanner tab.
///
/// Layer 1 — runs immediately on file pick (local only, no network).
/// Layer 2 — hash-only reputation lookup (user-triggered, sends SHA-256 only).
/// Layer 3 — full upload to VirusTotal (explicit per-file consent dialog required).
class FileScannerTab extends StatefulWidget {
  const FileScannerTab({super.key});

  @override
  State<FileScannerTab> createState() => _FileScannerTabState();
}

class _FileScannerTabState extends State<FileScannerTab> {
  // ── State ────────────────────────────────────────────────────────────────
  String? _fileName;
  FileScanResult? _localResult;
  bool _isLoadingReputation = false;
  String? _reputationVerdict;
  String? _reputationDetail;
  bool _isUploadingFullScan = false;
  String? _fullScanAnalysisUrl;
  String? _errorMessage;

  // ── File selection (simulated — caller wires up real picker) ─────────────

  /// Called by the "Choose File" button.  In a real app this would use
  /// file_selector or file_picker to let the user browse their device.
  /// Here we accept bytes directly so the widget stays testable without a
  /// platform plugin.
  void _onFilePicked(String name, Uint8List bytes) {
    setState(() {
      _fileName = name;
      _localResult = FileScanner.scanLocal(name, bytes);
      _reputationVerdict = null;
      _reputationDetail = null;
      _fullScanAnalysisUrl = null;
      _errorMessage = null;
    });
  }

  /// Simulates picking a file for demo purposes.
  void _simulateFilePick() {
    // PDF magic bytes — a clean, well-known file type.
    final demoBytes = Uint8List.fromList([
      0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34,
    ]);
    _onFilePicked('annual_report.pdf', demoBytes);
  }

  // ── Layer 2: hash reputation lookup ──────────────────────────────────────

  Future<void> _checkReputation() async {
    if (_localResult == null) return;

    setState(() {
      _isLoadingReputation = true;
      _reputationVerdict = null;
      _reputationDetail = null;
      _errorMessage = null;
    });

    try {
      // In production: POST to backend /file-reputation/hash-lookup with sha256.
      // Simulated response for demonstration.
      await Future.delayed(const Duration(milliseconds: 700));
      setState(() {
        _reputationVerdict = 'clean';
        _reputationDetail = '0 / 72 AV engines flagged this file.';
        _localResult = _localResult!.withReputation('clean');
      });
    } catch (e) {
      setState(() => _errorMessage = 'Reputation check failed: $e');
    } finally {
      setState(() => _isLoadingReputation = false);
    }
  }

  // ── Layer 3: full scan disclosure dialog + upload ─────────────────────────

  /// Shows the per-file consent dialog required before any full upload.
  Future<bool> _showFullScanDisclosure() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.cloud_upload_outlined, color: Color(0xFFFF8906)),
                SizedBox(width: 10),
                Text('Third-Party Upload Disclosure'),
              ],
            ),
            content: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.6),
                children: [
                  const TextSpan(text: 'You are about to upload\n\n'),
                  TextSpan(
                    text: '  $_fileName\n\n',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF8906),
                    ),
                  ),
                  const TextSpan(
                    text:
                        'to VirusTotal (virustotal.com), a third-party security '
                        'scanning service operated by Google.\n\n'
                        'By proceeding, the complete file contents will be sent '
                        'to VirusTotal and may be stored and shared with '
                        'their security research partners.\n\n'
                        'This is a per-file decision. No global opt-in is stored.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8906),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Upload to VirusTotal'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runFullScan() async {
    if (_localResult == null) return;

    final consented = await _showFullScanDisclosure();
    if (!consented) return;

    setState(() {
      _isUploadingFullScan = true;
      _errorMessage = null;
      _fullScanAnalysisUrl = null;
    });

    try {
      // In production: POST file bytes to backend /file-reputation/full-scan
      // with x-user-consent: true header set.
      // Simulated response for demonstration.
      await Future.delayed(const Duration(milliseconds: 1000));
      setState(() {
        _fullScanAnalysisUrl =
            'https://www.virustotal.com/gui/file/${_localResult!.sha256}/detection';
      });
    } catch (e) {
      setState(() => _errorMessage = 'Full scan failed: $e');
    } finally {
      setState(() => _isUploadingFullScan = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'File Security Scanner',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Three-layer analysis: local magic-byte checks → hash reputation '
            '→ full VirusTotal scan (requires consent).',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 20),

          // ── File picker ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  // ignore: deprecated_member_use
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _simulateFilePick,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(
                _fileName == null ? 'Choose a File…' : 'Change File',
              ),
            ),
          ),

          if (_fileName != null) ...[
            const SizedBox(height: 12),
            _FileNameBadge(fileName: _fileName!),
          ],

          // ── Layer 1 results ─────────────────────────────────────────────
          if (_localResult != null) ...[
            const SizedBox(height: 24),
            _SectionHeader(
              icon: Icons.computer,
              label: 'Layer 1 — Local Checks',
              subtitle: 'No network required',
            ),
            const SizedBox(height: 12),
            _Layer1ResultCard(result: _localResult!),

            const SizedBox(height: 20),

            // ── Layer 2 button + result ────────────────────────────────────
            _SectionHeader(
              icon: Icons.cloud_outlined,
              label: 'Layer 2 — Hash Reputation',
              subtitle: 'Sends SHA-256 only — file stays on device',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isLoadingReputation ? null : _checkReputation,
                icon: _isLoadingReputation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _isLoadingReputation
                      ? 'Checking reputation…'
                      : 'Check Hash Reputation',
                ),
              ),
            ),
            if (_reputationVerdict != null) ...[
              const SizedBox(height: 12),
              _ReputationCard(
                verdict: _reputationVerdict!,
                detail: _reputationDetail ?? '',
                sha256: _localResult!.sha256,
              ),
            ],

            // ── Layer 3 (only shown when verdict is unknown) ───────────────
            if (_reputationVerdict == 'unknown') ...[
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.cloud_upload_outlined,
                label: 'Layer 3 — Full Upload Scan',
                subtitle: 'Sends file contents to VirusTotal — requires consent',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color: const Color(0xFFFF8906).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    // ignore: deprecated_member_use
                    color: const Color(0xFFFF8906).withOpacity(0.2),
                  ),
                ),
                child: const Text(
                  'This file has not been seen before. A full upload to '
                  'VirusTotal will send the complete file contents to a '
                  'third-party service. A per-file consent dialog will '
                  'appear before any upload begins.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8906),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isUploadingFullScan ? null : _runFullScan,
                  icon: _isUploadingFullScan
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(
                    _isUploadingFullScan ? 'Uploading…' : 'Full Scan (opt-in)',
                  ),
                ),
              ),
            ],

            if (_fullScanAnalysisUrl != null) ...[
              const SizedBox(height: 12),
              _FullScanResultCard(analysisUrl: _fullScanAnalysisUrl!),
            ],
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorCard(message: _errorMessage!),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            Text(subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ],
    );
  }
}

class _FileNameBadge extends StatelessWidget {
  final String fileName;
  const _FileNameBadge({required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withAlpha(51)),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Layer1ResultCard extends StatelessWidget {
  final FileScanResult result;
  const _Layer1ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final safe = !result.isMalicious;
    final accent = safe ? const Color(0xFF00E676) : const Color(0xFFFF5252);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        // ignore: deprecated_member_use
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall verdict row
          Row(
            children: [
              Icon(
                safe ? Icons.verified_outlined : Icons.gpp_bad_outlined,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                safe ? 'No Local Threats Detected' : 'Threats Detected Locally',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // SHA-256 display (truncated)
          Text(
            'SHA-256: ${result.sha256.substring(0, 16)}…',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          // Indicator badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _IndicatorBadge(
                label: 'Signature Match',
                ok: !result.isSigMismatch,
                okLabel: 'OK',
                failLabel: 'MISMATCH',
              ),
              _IndicatorBadge(
                label: 'Extension',
                ok: !result.isDoubleExtension,
                okLabel: 'OK',
                failLabel: 'DOUBLE EXT',
              ),
              _IndicatorBadge(
                label: 'Macro',
                ok: !result.isMacroEnabled,
                okLabel: 'NONE',
                failLabel: 'DETECTED',
              ),
              _IndicatorBadge(
                label: 'Detected Type',
                ok: true,
                okLabel: result.detectedType.name.toUpperCase(),
                failLabel: '',
                isInfo: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IndicatorBadge extends StatelessWidget {
  final String label;
  final bool ok;
  final String okLabel;
  final String failLabel;
  final bool isInfo;

  const _IndicatorBadge({
    required this.label,
    required this.ok,
    required this.okLabel,
    required this.failLabel,
    this.isInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isInfo
        ? const Color(0xFF6C63FF)
        : ok
            ? const Color(0xFF00E676)
            : const Color(0xFFFF5252);
    final statusText = isInfo ? okLabel : (ok ? okLabel : failLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.grey)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            // ignore: deprecated_member_use
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            // ignore: deprecated_member_use
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReputationCard extends StatelessWidget {
  final String verdict;
  final String detail;
  final String sha256;

  const _ReputationCard({
    required this.verdict,
    required this.detail,
    required this.sha256,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    switch (verdict) {
      case 'malicious':
        color = const Color(0xFFFF5252);
        icon = Icons.gpp_bad_outlined;
      case 'suspicious':
        color = const Color(0xFFFF8906);
        icon = Icons.warning_amber_rounded;
      case 'clean':
        color = const Color(0xFF00E676);
        icon = Icons.verified_user_outlined;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        // ignore: deprecated_member_use
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VirusTotal: ${verdict.toUpperCase()}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(detail,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScanResultCard extends StatelessWidget {
  final String analysisUrl;
  const _FullScanResultCard({required this.analysisUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: const Color(0xFF00E676).withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        // ignore: deprecated_member_use
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: Color(0xFF00E676), size: 18),
              SizedBox(width: 8),
              Text('File Submitted to VirusTotal',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            analysisUrl,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: const Color(0xFFFF5252).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        // ignore: deprecated_member_use
        border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF5252)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFFF5252)),
            ),
          ),
        ],
      ),
    );
  }
}
