import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/main.dart';
import 'package:net_route_scout/ui/views/widgets/node_card_widget.dart';

void main() {
  tearDown(() {
    AppTheme.isDark = true;
  });

  group('AppTheme dynamic light & dark tokens', () {
    test('dark mode returns dark palette matching LIGHT_MODE_SPECIFICATION', () {
      AppTheme.isDark = true;

      expect(AppTheme.scaffoldBg, const Color(0xFF141414));
      expect(AppTheme.windowBg, const Color(0xFF141414));
      expect(AppTheme.surface, const Color(0xFF1E1E1E));
      expect(AppTheme.surfaceHigh, const Color(0xFF252526));
      expect(AppTheme.inputFill, const Color(0xFF252526));
      expect(AppTheme.border, const Color(0xFF2C2C2C));
      expect(AppTheme.textPrimary, const Color(0xFFE0E0E0));
      expect(AppTheme.textSecondary, const Color(0xFF9E9E9E));
      expect(AppTheme.textMuted, const Color(0xFF6E6E6E));
      expect(AppTheme.accent, const Color(0xFF007ACC));
      expect(AppTheme.success, const Color(0xFF10B981));
      expect(AppTheme.error, const Color(0xFFEF4444));
      expect(AppTheme.warning, const Color(0xFFF59E0B));
      expect(AppTheme.info, const Color(0xFF3B82F6));
      expect(AppTheme.currentTheme.brightness, Brightness.dark);
    });

    test('light mode returns light palette matching LIGHT_MODE_SPECIFICATION', () {
      AppTheme.isDark = false;

      expect(AppTheme.scaffoldBg, const Color(0xFFF3F4F6));
      expect(AppTheme.windowBg, const Color(0xFFF3F4F6));
      expect(AppTheme.surface, const Color(0xFFFFFFFF));
      expect(AppTheme.surfaceHigh, const Color(0xFFF9FAFB));
      expect(AppTheme.inputFill, const Color(0xFFF9FAFB));
      expect(AppTheme.border, const Color(0xFFE5E7EB));
      expect(AppTheme.textPrimary, const Color(0xFF111827));
      expect(AppTheme.textSecondary, const Color(0xFF4B5563));
      expect(AppTheme.textMuted, const Color(0xFF6B7280));
      expect(AppTheme.accent, const Color(0xFF0284C7));
      expect(AppTheme.success, const Color(0xFF059669));
      expect(AppTheme.error, const Color(0xFFDC2626));
      expect(AppTheme.warning, const Color(0xFFD97706));
      expect(AppTheme.info, const Color(0xFF2563EB));
      expect(AppTheme.currentTheme.brightness, Brightness.light);
    });

    test('lightTheme() and darkTheme() do not mutate AppTheme.isDark', () {
      AppTheme.isDark = false;
      final dark = AppTheme.darkTheme();
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF141414));
      expect(AppTheme.isDark, isFalse);

      AppTheme.isDark = true;
      final light = AppTheme.lightTheme();
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, const Color(0xFFF3F4F6));
      expect(AppTheme.isDark, isTrue);
    });
  });

  group('Widget rendering in Dark and Light modes', () {
    testWidgets('NetRouteScoutApp applies light ThemeMode when AppTheme.isDark is false',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      AppTheme.isDark = false;
      await tester.pumpWidget(const NetRouteScoutApp());
      await tester.pump(const Duration(milliseconds: 100));

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);
      expect(materialApp.theme?.brightness, Brightness.light);
      expect(materialApp.darkTheme?.brightness, Brightness.dark);
    });

    testWidgets('NodeCardWidget renders cleanly in both dark and light modes',
        (WidgetTester tester) async {
      final node = NetworkNode(
        id: '192.168.1.1',
        ip: '192.168.1.1',
        hostname: 'gw.local',
        hopDepth: 1,
        isTarget: true,
      );

      for (final dark in [true, false]) {
        AppTheme.isDark = dark;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: Scaffold(
              body: Center(
                child: NodeCardWidget(
                  node: node,
                  isSelected: false,
                  isOnActivePath: false,
                  isDimmed: false,
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.text('192.168.1.1'), findsOneWidget);
        expect(find.text('gw.local'), findsOneWidget);
      }
    });
  });
}
