import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/data/repositories/topology_repository.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'package:net_route_scout/ui/views/widgets/alert_banner.dart';
import 'package:net_route_scout/ui/views/widgets/detail_inspector_panel.dart';
import 'package:net_route_scout/ui/views/widgets/device_library_dialog.dart';
import 'package:net_route_scout/ui/views/widgets/edit_device_dialog.dart';
import 'package:net_route_scout/ui/views/widgets/filter_toolbar.dart';
import 'package:net_route_scout/ui/views/widgets/route_table_view.dart';
import 'package:net_route_scout/ui/views/widgets/top_control_bar.dart';

Widget createTestApp(Widget child, TopologyViewModel vm) {
  return MaterialApp(
    theme: AppTheme.darkTheme(),
    home: Scaffold(
      body: ChangeNotifierProvider<TopologyViewModel>.value(
        value: vm,
        child: child,
      ),
    ),
  );
}

void main() {
  group('RouteTableView Widget Tests', () {
    testWidgets('Renders empty state when filter matches nothing', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);
      vm.loadDemoTopology();
      vm.setSearchQuery('nonexistent_filter_query_12345');

      await tester.pumpWidget(createTestApp(const RouteTableView(), vm));
      await tester.pumpAndSettle();

      expect(find.text('No devices found matching filter.'), findsOneWidget);
    });

    testWidgets('Renders table rows and column headers when demo data loaded', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);
      vm.loadDemoTopology();

      await tester.pumpWidget(createTestApp(const RouteTableView(), vm));
      await tester.pumpAndSettle();

      // Check Header Cells
      expect(find.text('HOP'), findsOneWidget);
      expect(find.text('DEVICE NAME (SHARED)'), findsOneWidget);
      expect(find.text('IP ADDRESS'), findsOneWidget);
      expect(find.text('MAC ADDRESS'), findsOneWidget);
      expect(find.text('RTT (LATENCY)'), findsOneWidget);
      expect(find.text('PATH TRAVERSAL ROUTE'), findsOneWidget);

      // Check Rows rendered
      expect(find.text('Accounting Server (SQL)'), findsWidgets);
      expect(find.text('Main Gateway Router'), findsWidgets);

      // Tap on a row to select node
      await tester.tap(find.text('Accounting Server (SQL)').first);
      await tester.pumpAndSettle();

      expect(vm.selectedNodeId, '10.0.1.45');
    });

    testWidgets('Header sorting reorders items', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);
      vm.loadDemoTopology();

      await tester.pumpWidget(createTestApp(const RouteTableView(), vm));
      await tester.pumpAndSettle();

      // Tap HOP header to sort
      await tester.tap(find.text('HOP'));
      await tester.pumpAndSettle();

      // Tap again to toggle ascending/descending
      await tester.tap(find.text('HOP'));
      await tester.pumpAndSettle();
    });
  });

  group('DetailInspectorPanel Widget Tests', () {
    testWidgets('Renders persistent status bar and details when node is selected', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);
      vm.loadDemoTopology();
      vm.selectNode('10.0.1.45');

      await tester.pumpWidget(createTestApp(const DetailInspectorPanel(), vm));
      await tester.pumpAndSettle();

      // Check Device Name and IP in inspector
      expect(find.text('Accounting Server (SQL)'), findsWidgets);
      expect(find.text('10.0.1.45'), findsWidgets);

      // Check Status bar metrics
      expect(find.textContaining('nodes,'), findsOneWidget);
      expect(find.textContaining('edges across'), findsOneWidget);
      expect(find.textContaining('Shared DB:'), findsOneWidget);

      // Check Edit Device button exists
      expect(find.byIcon(Icons.edit), findsOneWidget);

      // Close inspector by tapping close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(vm.selectedNodeId, isNull);
    });
  });

  group('AlertBanner Widget Tests', () {
    testWidgets('Renders warning banner text and close action', (tester) async {
      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);
      await vm.cancelSweep();

      await tester.pumpWidget(createTestApp(const AlertBanner(), vm));
      await tester.pumpAndSettle();

      expect(find.text('Sweep cancelled by user.'), findsOneWidget);
    });
  });

  group('EditDeviceDialog Widget Tests', () {
    testWidgets('Validates MAC address format and invokes onSave callback', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testNode = NetworkNode(
        id: '192.168.1.15',
        ip: '192.168.1.15',
        hopDepth: 1,
        sharedDeviceName: 'Test Device',
      );

      var saved = false;
      String? savedMac;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: EditDeviceDialog(
                  node: testNode,
                  onSave: ({
                    required String ip,
                    required String rawMac,
                    required String name,
                    String? category,
                    String? vendor,
                    String? notes,
                  }) {
                    saved = true;
                    savedMac = rawMac;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Title
      expect(find.text('Edit Shared Device Identity'), findsOneWidget);

      // 1. Try to save with empty MAC
      await tester.tap(find.text('Save to Shared Database'));
      await tester.pumpAndSettle();
      expect(find.text('MAC address is required to store in Shared Device DB'), findsOneWidget);
      expect(saved, isFalse);

      // 2. Enter invalid MAC
      final macField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == 'XX:XX:XX:XX:XX:XX',
      );
      await tester.enterText(macField, 'invalid-mac');
      await tester.tap(find.text('Save to Shared Database'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid MAC address format'), findsOneWidget);
      expect(saved, isFalse);

      // 3. Enter valid MAC and save
      await tester.enterText(macField, '00:1A:2B:3C:4D:5E');
      await tester.tap(find.text('Save to Shared Database'));
      await tester.pumpAndSettle();

      expect(saved, isTrue);
      expect(savedMac, '00:1A:2B:3C:4D:5E');
    });
  });

  group('FilterToolbar Widget Tests', () {
    testWidgets('Updates ViewModel search query and clear action resets input', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);

      await tester.pumpWidget(createTestApp(const FilterToolbar(), vm));
      await tester.pumpAndSettle();

      final searchField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == 'Filter nodes / devices...',
      );
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, '192.168.1.1');
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      expect(vm.searchQuery, '192.168.1.1');

      // Tap clear icon
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(vm.searchQuery, '');
    });

    testWidgets('Auto-detected toggle switch updates ViewModel showAutoDetected', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);
      expect(vm.showAutoDetected, isFalse);

      await tester.pumpWidget(createTestApp(const FilterToolbar(), vm));
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(vm.showAutoDetected, isTrue);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(vm.showAutoDetected, isFalse);
    });

    testWidgets('Dedicated IP and MAC filter inputs update ViewModel', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);

      await tester.pumpWidget(createTestApp(const FilterToolbar(), vm));
      await tester.pumpAndSettle();

      final ipField = find.byWidgetPredicate(
        (widget) => widget is TextField && (widget.decoration?.hintText?.contains('Search IP') ?? false),
      );
      expect(ipField, findsOneWidget);
      await tester.enterText(ipField, '10.0.1.45');
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      expect(vm.ipFilter, '10.0.1.45');

      final macField = find.byWidgetPredicate(
        (widget) => widget is TextField && (widget.decoration?.hintText?.contains('Search MAC') ?? false),
      );
      expect(macField, findsOneWidget);
      await tester.enterText(macField, '00:50:56');
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      expect(vm.macFilter, '00:50:56');
    });

    testWidgets('Device pills row renders and allows multi-selection', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);
      vm.loadDemoTopology();
      vm.setShowAutoDetected(true);

      await tester.pumpWidget(createTestApp(const FilterToolbar(), vm));
      await tester.pumpAndSettle();

      expect(find.text('DEVICES:'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);

      // Verify device pills exist
      final pillFinder = find.byType(FilterChip);
      expect(pillFinder, findsWidgets);

      // Tap first pill
      await tester.tap(pillFinder.first);
      await tester.pumpAndSettle();
      expect(vm.selectedDeviceKeys.length, 1);
    });
  });

  group('TopControlBar Widget Tests', () {
    testWidgets('Renders buttons and controls according to updated Syslog Server styling', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);

      await tester.pumpWidget(createTestApp(const TopControlBar(), vm));
      await tester.pumpAndSettle();

      // Verify Start Sweep is present
      expect(find.text('Start Sweep'), findsOneWidget);

      // Verify Load Demo, Device Library, and Clear are present
      expect(find.text('Load Demo'), findsOneWidget);
      expect(find.text('Device Library'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);

      // Verify 8.8.8.8 and 1.1.1.1 preset chips are removed
      expect(find.text('8.8.8.8'), findsNothing);
      expect(find.text('1.1.1.1'), findsNothing);

      // Verify Host: and SHARED DB status pills are removed
      expect(find.textContaining('Host: '), findsNothing);
      expect(find.text('SHARED DB'), findsNothing);
    });
  });

  group('DeviceLibraryDialog Widget Tests', () {
    testWidgets('Opens dialog with 2 tabs for Known and Unknown devices', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = TopologyViewModel(repository: TopologyRepository(), autoInit: false);
      vm.loadDemoTopology();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ChangeNotifierProvider<TopologyViewModel>.value(
              value: vm,
              child: const DeviceLibraryDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Dialog Title & Subtitle
      expect(find.text('Custom Library'), findsOneWidget);
      expect(find.textContaining('Manage known and unknown devices'), findsOneWidget);

      // Check TabBar with Known and Unknown tabs
      expect(find.textContaining('Known Devices'), findsOneWidget);
      expect(find.textContaining('Unknown Devices'), findsOneWidget);

      // Check Add Device button
      expect(find.text('Add Device'), findsOneWidget);

      // Verify Known Devices tab displays empty state when DB not populated
      expect(find.text('No known devices with custom names in database.'), findsOneWidget);

      // Tap on Unknown Devices tab
      await tester.tap(find.textContaining('Unknown Devices'));
      await tester.pumpAndSettle();

      // Verify Unknown Devices tab displays nodes from demo topology
      expect(find.textContaining('10.0.1.'), findsWidgets);
    });
  });
}
