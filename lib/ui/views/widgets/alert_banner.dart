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

    if (!progress.isScanning && statusMsg == null) {
      return const SizedBox.shrink();
    }

    if (progress.isScanning) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primaryAccent.withValues(alpha: 0.1),
          border: const Border(
            bottom: BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryAccent,
                    ),
                  ),
                ),
                if (progress.currentTarget != null)
                  Text(
                    'Probing: ${progress.currentTarget}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                const SizedBox(width: 12),
                Text(
                  '${progress.completedTargets} / ${progress.totalTargets} (${progress.percentage}%)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 24,
                  child: TextButton.icon(
                    onPressed: vm.cancelSweep,
                    icon: const Icon(Icons.stop_circle, size: 14, color: Color(0xFFEF4444)),
                    label: const Text(
                      'Stop Scan',
                      style: TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
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
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                minHeight: 3,
              ),
            ),
          ],
        ),
      );
    }

    // Status warning / message banner
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF59E0B), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusMsg ?? '',
              style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B)),
            ),
          ),
          IconButton(
            onPressed: () => vm.clearSelection(),
            icon: const Icon(Icons.close, size: 14, color: Colors.white54),
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
