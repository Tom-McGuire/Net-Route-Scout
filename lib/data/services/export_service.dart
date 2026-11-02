import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../../domain/models/network_edge.dart';
import '../../domain/models/network_node.dart';
import '../../domain/models/trace_result.dart';

class ExportService {
  /// Exports topology data to a JSON file chosen by the user.
  static Future<String?> exportToJsonFile({
    required Map<String, NetworkNode> nodes,
    required Map<String, NetworkEdge> edges,
    required List<TraceResult> traces,
    required String localHostIp,
  }) async {
    final exportData = {
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'Net Route Scout',
      'local_host_ip': localHostIp,
      'statistics': {
        'total_nodes': nodes.length,
        'total_edges': edges.length,
        'total_targets': traces.length,
      },
      'nodes': nodes.values.map((n) => n.toJson()).toList(),
      'edges': edges.values.map((e) => e.toJson()).toList(),
      'traces': traces.map((t) => t.toJson()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
    final bytes = Uint8List.fromList(utf8.encode(jsonString));

    try {
      final defaultName = 'network_topology_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.json';
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export Network Topology JSON',
        fileName: defaultName,
        bytes: bytes,
      );

      if (uri != null) {
        try {
          return uri.toFilePath();
        } catch (_) {
          return uri.path;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Copies JSON topology to system clipboard.
  static Future<void> copyJsonToClipboard({
    required Map<String, NetworkNode> nodes,
    required Map<String, NetworkEdge> edges,
    required List<TraceResult> traces,
    required String localHostIp,
  }) async {
    final exportData = {
      'exported_at': DateTime.now().toIso8601String(),
      'app': 'Net Route Scout',
      'local_host_ip': localHostIp,
      'statistics': {
        'total_nodes': nodes.length,
        'total_edges': edges.length,
        'total_targets': traces.length,
      },
      'nodes': nodes.values.map((n) => n.toJson()).toList(),
      'edges': edges.values.map((e) => e.toJson()).toList(),
      'traces': traces.map((t) => t.toJson()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
    await Clipboard.setData(ClipboardData(text: jsonString));
  }
}
