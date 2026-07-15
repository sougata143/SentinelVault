import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';

class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: VaultSyncManager.statusStream,
      initialData: VaultSyncManager.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;

        switch (status) {
          case SyncStatus.syncing:
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                ),
              ),
            );
          case SyncStatus.error:
            return const Tooltip(
              message: 'Sync pending (connection offline or error)',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, color: Colors.orange, size: 18),
                    SizedBox(width: 4),
                    Text(
                      'Pending',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          case SyncStatus.success:
            return const Tooltip(
              message: 'Vault is fully synchronized',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Icon(Icons.cloud_done, color: Colors.green, size: 18),
              ),
            );
          case SyncStatus.idle:
            return const SizedBox.shrink();
        }
      },
    );
  }
}
