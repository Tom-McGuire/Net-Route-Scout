import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/topology_diff_result.dart';
import 'package:net_route_scout/domain/models/topology_snapshot.dart';

class DiffSummaryDrawer extends StatelessWidget {
  final TopologySnapshot baseline;
  final TopologyDiffResult diffResult;
  final ValueChanged<String> onFocusTarget;
  final VoidCallback onClose;
  final VoidCallback? onExportBaseline;

  const DiffSummaryDrawer({
    super.key,
    required this.baseline,
    required this.diffResult,
    required this.onFocusTarget,
    required this.onClose,
    this.onExportBaseline,
  });

  @override
  Widget build(BuildContext context) {
    final criticalCount = diffResult.criticalCount;
    final warningCount = diffResult.items.where((i) => !i.isCritical).length;

    return Container(
      width: 360,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceContainer,
        border: Border(
          left: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: AppTheme.border),
          _buildSummaryBar(criticalCount, warningCount),
          const Divider(height: 1, color: AppTheme.border),
          Expanded(
            child: diffResult.hasDrift
                ? ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: diffResult.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _buildDiffItemCard(diffResult.items[index]),
                  )
                : _buildAllMatchState(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final accentColor = diffResult.criticalCount > 0
        ? const Color(0xFFEF4444)
        : (diffResult.hasDrift ? const Color(0xFFF59E0B) : AppTheme.primaryAccent);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: AppTheme.surfaceContainerLow,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.compare_arrows, size: 16, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Baseline Diff',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  baseline.name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white60,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onExportBaseline != null)
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 17, color: Colors.white70),
              tooltip: 'Export Baseline Snapshot',
              splashRadius: 16,
              visualDensity: VisualDensity.compact,
              onPressed: onExportBaseline,
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 17, color: Colors.white54),
            tooltip: 'Close Diff Summary',
            splashRadius: 16,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(int criticalCount, int warningCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.surface,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (!diffResult.hasDrift)
                  _buildSummaryChip(
                    label: 'All Match',
                    color: const Color(0xFF10B981),
                    icon: Icons.check_circle_outline,
                  )
                else ...[
                  if (criticalCount > 0)
                    _buildSummaryChip(
                      label: 'Critical: $criticalCount',
                      color: const Color(0xFFEF4444),
                      icon: Icons.error_outline,
                    ),
                  if (warningCount > 0)
                    _buildSummaryChip(
                      label: 'Warnings: $warningCount',
                      color: const Color(0xFFF59E0B),
                      icon: Icons.warning_amber_rounded,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTimestamp(baseline.createdAt),
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllMatchState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_outlined,
                size: 30,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'All Match',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Live topology matches "${baseline.name}" across ${baseline.nodes.length} nodes and ${baseline.edges.length} links.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffItemCard(TopologyDiffItem item) {
    final (String typeLabel, Color accentColor, IconData icon) = switch (item.type) {
      DiffChangeType.missing => ('MISSING', const Color(0xFFEF4444), Icons.remove_circle_outline),
      DiffChangeType.added => ('NEW', const Color(0xFF10B981), Icons.add_circle_outline),
      DiffChangeType.roleChanged => ('ROLE SHIFT', const Color(0xFFEF4444), Icons.swap_horiz),
      DiffChangeType.stpStateChanged => ('STP STATE', const Color(0xFFEF4444), Icons.alt_route),
      DiffChangeType.linkDegraded => ('DEGRADED', const Color(0xFFF59E0B), Icons.speed),
      DiffChangeType.unchanged => ('MATCH', Colors.white54, Icons.check),
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.isCritical
              ? accentColor.withValues(alpha: 0.45)
              : AppTheme.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accentColor.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 11, color: accentColor),
                    const SizedBox(width: 4),
                    Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (item.isCritical)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'CRITICAL',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                item.isEdge ? 'LINK' : 'NODE',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                _buildComparisonRow('Baseline', item.baselineValue, Colors.white60),
                const SizedBox(height: 4),
                _buildComparisonRow('Current', item.currentValue, accentColor),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.targetId,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.white38,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 26,
                child: OutlinedButton.icon(
                  onPressed: () => onFocusTarget(item.targetId),
                  icon: const Icon(Icons.center_focus_strong, size: 13, color: AppTheme.primaryAccent),
                  label: const Text(
                    'Focus',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryAccent, width: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String label, String value, Color valueColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.white38),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: valueColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  static String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}
