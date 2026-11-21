import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';

class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();
    final progress = vm.scanProgress;
    final statusMsg = vm.statusBannerText;
    final l2Alerts = vm.visibleL2DiagnosticAlerts;

    if (!progress.isScanning && statusMsg == null && l2Alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    if (progress.isScanning) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primaryAccent.withValues(alpha: 0.1),
          border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    progress.phase,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryAccent,
                    ),
                  ),
                ),
                if (progress.currentTarget != null)
                  Text(
                    'Probing: ${progress.currentTarget}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppTheme.textSecondary,
                    ),
                  ),
                const SizedBox(width: 12),
                Text(
                  '${progress.completedTargets} / ${progress.totalTargets} (${progress.percentage}%)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 24,
                  child: TextButton.icon(
                    onPressed: vm.cancelSweep,
                    icon: Icon(Icons.stop_circle, size: 14, color: AppTheme.error),
                    label: Text(
                      'Stop Scan',
                      style: TextStyle(fontSize: 11, color: AppTheme.error),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      backgroundColor: AppTheme.error.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.fraction > 0 ? progress.fraction : null,
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                minHeight: 3,
              ),
            ),
          ],
        ),
      );
    }

    // Status warning / message banner or L2 diagnostics
    final displayMessage = statusMsg ?? l2Alerts.join('  •  ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(color: AppTheme.warning, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: displayMessage,
              child: Text(
                displayMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppTheme.warning),
              ),
            ),
          ),
          IconButton(
            onPressed: vm.dismissAlertBanner,
            icon: Icon(Icons.close, size: 14, color: AppTheme.textMuted),
            tooltip: 'Dismiss alert',
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
