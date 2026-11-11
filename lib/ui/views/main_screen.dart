import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../view_models/topology_view_model.dart';
import 'widgets/alert_banner.dart';
import 'widgets/detail_inspector_panel.dart';
import 'widgets/filter_toolbar.dart';
import 'widgets/route_table_view.dart';
import 'widgets/top_control_bar.dart';
import 'widgets/topology_canvas.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final vm = Provider.of<TopologyViewModel>(context, listen: false);
    if (vm.isScanning) {
      await vm.cancelSweep();
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();

    return Scaffold(
      body: Column(
        children: [
          // 1. Top Control Bar
          const TopControlBar(),

          // 2. Global Alert / Progress Banner
          const AlertBanner(),

          // 3. Filter & Target Input Toolbar
          const FilterToolbar(),

          // 4. Primary Data Workspace (Expanded)
          Expanded(
            child: _buildWorkspace(vm.viewMode),
          ),

          // 5. Collapsible Detail Inspector & Status Bar
          const DetailInspectorPanel(),
        ],
      ),
    );
  }

  Widget _buildWorkspace(TopologyViewMode mode) {
    switch (mode) {
      case TopologyViewMode.graph:
        return const TopologyCanvas();
      case TopologyViewMode.table:
        return const RouteTableView();
      case TopologyViewMode.split:
        return const Row(
          children: [
            Expanded(
              flex: 3,
              child: TopologyCanvas(),
            ),
            VerticalDivider(width: 1),
            Expanded(
              flex: 2,
              child: RouteTableView(),
            ),
          ],
        );
    }
  }
}
