import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';

/// Live-updating TOTP / Authenticator code display card.
///
/// Features:
/// - Encapsulated timer updating every second without rebuilding parent widgets.
/// - Formatted 6-digit / 8-digit code with monospaced font.
/// - Circular progress indicator showing remaining seconds in current period.
/// - One-tap copy to clipboard with SnackBar confirmation.
class TotpCodeCard extends StatefulWidget {
  final String issuer;
  final String accountName;
  final String secret;
  final String algorithm;
  final int digits;
  final int period;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const TotpCodeCard({
    super.key,
    required this.issuer,
    required this.accountName,
    required this.secret,
    this.algorithm = 'SHA1',
    this.digits = 6,
    this.period = 30,
    this.onDelete,
    this.onEdit,
  });

  factory TotpCodeCard.fromFields({
    Key? key,
    required TotpFields fields,
    VoidCallback? onDelete,
    VoidCallback? onEdit,
  }) {
    return TotpCodeCard(
      key: key,
      issuer: fields.issuer,
      accountName: fields.accountName,
      secret: fields.secret.plaintext ?? '',
      algorithm: fields.algorithm,
      digits: fields.digits,
      period: fields.period,
      onDelete: onDelete,
      onEdit: onEdit,
    );
  }

  @override
  State<TotpCodeCard> createState() => _TotpCodeCardState();
}

class _TotpCodeCardState extends State<TotpCodeCard> {
  Timer? _timer;
  late String _currentCode;
  late int _remainingSeconds;
  late double _progress;

  @override
  void initState() {
    super.initState();
    _updateCode();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCode());
  }

  @override
  void didUpdateWidget(TotpCodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secret != widget.secret ||
        oldWidget.period != widget.period ||
        oldWidget.digits != widget.digits ||
        oldWidget.algorithm != widget.algorithm) {
      _updateCode();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateCode() {
    if (!mounted) return;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final period = widget.period <= 0 ? 30 : widget.period;
    final remaining = period - (nowSec % period);
    final progress = remaining / period;

    String code;
    try {
      if (widget.secret.trim().isEmpty) {
        code = '------';
      } else {
        code = TotpHelper.generateTotpCode(
          secret: widget.secret,
          timestampSec: nowSec,
          period: widget.period,
          digits: widget.digits,
          algorithm: widget.algorithm,
        );
      }
    } catch (_) {
      code = 'ERROR';
    }

    setState(() {
      _currentCode = code;
      _remainingSeconds = remaining;
      _progress = progress;
    });
  }

  String _formatCode(String code) {
    if (code.length == 6) {
      return '${code.substring(0, 3)} ${code.substring(3)}';
    } else if (code.length == 8) {
      return '${code.substring(0, 4)} ${code.substring(4)}';
    }
    return code;
  }

  void _copyToClipboard() {
    final rawCode = _currentCode.replaceAll(' ', '');
    Clipboard.setData(ClipboardData(text: rawCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 8),
            Text('Copied $rawCode to clipboard'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppTheme.surfaceColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _remainingSeconds <= 5;
    final progressColor = isUrgent ? AppTheme.errorColor : Colors.cyanAccent;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      elevation: 2,
      color: AppTheme.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.surfaceColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.issuer.isNotEmpty ? widget.issuer : 'Authenticator',
                        style: const TextStyle(
                          color: AppTheme.textPrimaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.accountName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.accountName,
                          style: const TextStyle(
                            color: AppTheme.textSecondaryColor,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.onEdit != null || widget.onDelete != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onEdit != null)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.textSecondaryColor),
                          onPressed: widget.onEdit,
                        ),
                      if (widget.onDelete != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                          onPressed: widget.onDelete,
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Code display + Copy tap area
                InkWell(
                  onTap: _copyToClipboard,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatCode(_currentCode),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                            color: isUrgent ? AppTheme.errorColor : Colors.cyanAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: AppTheme.textSecondaryColor,
                        ),
                      ],
                    ),
                  ),
                ),
                // Circular Timer
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 3.5,
                        backgroundColor: AppTheme.surfaceColor,
                        color: progressColor,
                      ),
                    ),
                    Text(
                      '$_remainingSeconds',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: progressColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
