import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/main.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';

void main() {
  testWidgets('NetRouteScoutApp launches and renders 5-tier desktop layout', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final vm = TopologyViewModel();

    await tester.pumpWidget(NetRouteScoutApp(viewModel: vm));
    await tester.pumpAndSettle();

    // Verify Title & Subtitle
    expect(find.text('NET ROUTE SCOUT'), findsOneWidget);
    expect(find.text('Visual Network Topology Mapper'), findsOneWidget);

    // Verify Controls & Buttons
    expect(find.text('Load Demo'), findsOneWidget);
    expect(find.text('Start Sweep'), findsOneWidget);
    expect(find.byIcon(Icons.radar), findsWidgets);

    // Verify Empty State is visible initially
    expect(find.text('No Network Routes Traced'), findsOneWidget);

    // Click Load Demo
    await tester.ensureVisible(find.text('Load Demo'));
    await tester.tap(find.text('Load Demo'));
    await tester.pumpAndSettle();

    // Verify Demo network loaded nodes
    expect(find.text('Accounting Server (SQL)'), findsWidgets);
    expect(find.text('Main Gateway Router'), findsWidgets);
  });
}
