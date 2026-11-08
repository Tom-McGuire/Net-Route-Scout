import 'dart:io';
import 'package:flutter/material.dart';
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

  // Safely initialize shared database
  try {
    await SharedDeviceDatabase.instance.init();
  } catch (e) {
    debugPrint('Shared device database fallback: $e');
  }

  final initialArgs = InterAppArguments.fromArgs(args);

  // If another instance of Net Route Scout is already running, attempt warm handoff
  if (initialArgs.target != null ||
      initialArgs.adapterIp != null ||
      initialArgs.adapterName != null ||
      initialArgs.autoStart) {
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
        target: incoming.target,
        adapterIp: incoming.adapterIp,
        adapterName: incoming.adapterName,
        autoStart: incoming.autoStart,
      );
    },
  );

  runApp(NetRouteScoutApp(viewModel: viewModel));
}

class NetRouteScoutApp extends StatelessWidget {
  const NetRouteScoutApp({super.key, this.viewModel});

  final TopologyViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel != null) {
      return ChangeNotifierProvider<TopologyViewModel>.value(
        value: viewModel!,
        child: MaterialApp(
          title: AppConstants.appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme(),
          home: const MainScreen(),
        ),
      );
    }

    return ChangeNotifierProvider<TopologyViewModel>(
      create: (_) => TopologyViewModel(),
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: const MainScreen(),
      ),
    );
  }
}
