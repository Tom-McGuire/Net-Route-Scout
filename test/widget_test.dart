import 'package:flutter/material.dart';
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
    expect(find.text('Net Route Scout'), findsOneWidget);
    expect(find.text('Visual Network Topology Mapper'), findsOneWidget);

    // Verify Controls & Buttons
    expect(find.text('Demo Network'), findsOneWidget);
    expect(find.text('Start Sweep'), findsOneWidget);
    expect(find.byIcon(Icons.radar), findsWidgets);

    // Verify Empty State is visible initially
    expect(find.text('No Network Routes Traced'), findsOneWidget);

    // Click Demo Network
    await tester.tap(find.text('Demo Network'));
    await tester.pumpAndSettle();

    // Verify Demo network loaded nodes
    expect(find.text('Accounting Server (SQL)'), findsWidgets);
    expect(find.text('Main Gateway Router'), findsWidgets);
  });
}
