import 'package:flutter/material.dart';

/// Modal dialog requiring the user to explicitly confirm out-of-band key fingerprint verification.
///
/// Gates share acceptance to defend against server-side public-key substitution (MITM).
class FingerprintVerificationDialog extends StatefulWidget {
  final String targetUserEmail;
  final String safetyNumber;

  const FingerprintVerificationDialog({
    super.key,
    required this.targetUserEmail,
    required this.safetyNumber,
  });

  @override
  State<FingerprintVerificationDialog> createState() => _FingerprintVerificationDialogState();
}

class _FingerprintVerificationDialogState extends State<FingerprintVerificationDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify Security Fingerprint'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To defend against intercept attacks, you must verify that the security keys for ${widget.targetUserEmail} match the safety numbers below.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                widget.safetyNumber,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Compare these numbers with their device (e.g. by scanning a QR code or reading these digits aloud over a secure channel). If they match, confirm below.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I have verified this safety number out-of-band',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              value: _confirmed,
              onChanged: (val) {
                setState(() {
                  _confirmed = val ?? false;
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _confirmed
              ? () => Navigator.of(context).pop(true)
              : null, // Disabled until checkbox is checked
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm Trust & Accept'),
        ),
      ],
    );
  }
}
