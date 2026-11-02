import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'core/constants.dart';
import 'ui/view_models/topology_view_model.dart';
import 'ui/views/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safely initialize shared database
  try {
    await SharedDeviceDatabase.instance.init();
  } catch (e) {
    debugPrint('Shared device database fallback: $e');
  }

  runApp(const NetRouteScoutApp());
}

class NetRouteScoutApp extends StatelessWidget {
  const NetRouteScoutApp({super.key, this.viewModel});

  final TopologyViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TopologyViewModel>(
      create: (_) => viewModel ?? TopologyViewModel(),
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: const MainScreen(),
      ),
    );
  }
}
