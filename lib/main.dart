import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'core/app_theme.dart';
import 'core/constants.dart';
import 'data/services/inter_app_ipc_service.dart';
import 'domain/models/inter_app_arguments.dart';
import 'ui/view_models/topology_view_model.dart';
import 'ui/views/main_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safely initialize shared database and synchronize initial theme mode
  try {
    await SharedDeviceDatabase.instance.init();
    final mode = await SharedDeviceDatabase.instance.getThemeMode();
    AppTheme.isDark = (mode == 'dark');
  } catch (e) {
    debugPrint('Shared device database fallback: $e');
  }

  final initialArgs = InterAppArguments.fromArgs(args);

  // If another instance of Net Route Scout is already running, attempt warm handoff
  if (initialArgs.hasCommand) {
    final delivered = await InterAppIpcService.sendCommand(
      port: InterAppIpcService.routeScoutIpcPort,
      payload: initialArgs.toJson(),
    );
    if (delivered) {
      exit(0);
    }
  }

  final viewModel = TopologyViewModel(initialArgs: initialArgs);

  // Start single-instance loopback IPC listener on port 44101
  await InterAppIpcService.startListener(
    InterAppIpcService.routeScoutIpcPort,
    (payload) {
      final incoming = InterAppArguments.fromJson(payload);
      viewModel.handleIncomingCommand(
        target: incoming.effectiveTarget,
        adapterIp: incoming.adapterIp,
        adapterName: incoming.adapterName,
        autoStart: incoming.autoStart,
      );
    },
  );

  runApp(NetRouteScoutApp(viewModel: viewModel));
}

class NetRouteScoutApp extends StatefulWidget {
  const NetRouteScoutApp({super.key, this.viewModel});

  final TopologyViewModel? viewModel;

  @override
  State<NetRouteScoutApp> createState() => _NetRouteScoutAppState();
}

class _NetRouteScoutAppState extends State<NetRouteScoutApp> {
  late String _themeMode;
  StreamSubscription<void>? _dbSub;

  @override
  void initState() {
    super.initState();
    _themeMode = AppTheme.isDark ? 'dark' : 'light';
    _dbSub = SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) {
      _syncTheme();
    });
  }

  Future<void> _syncTheme() async {
    try {
      final mode = await SharedDeviceDatabase.instance.getThemeMode();
      if (mode != _themeMode && mounted) {
        setState(() {
          _themeMode = mode;
          AppTheme.isDark = (mode == 'dark');
        });
      }
    } catch (e) {
      debugPrint('Failed to sync theme mode: $e');
    }
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: _themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light,
      home: KeyedSubtree(
        key: ValueKey(_themeMode),
        child: const MainScreen(),
      ),
    );

    if (widget.viewModel != null) {
      return ChangeNotifierProvider<TopologyViewModel>.value(
        value: widget.viewModel!,
        child: app,
      );
    }

    return ChangeNotifierProvider<TopologyViewModel>(
      create: (_) => TopologyViewModel(),
      child: app,
    );
  }
}
