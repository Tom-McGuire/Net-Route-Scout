import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:path/path.dart' as p;
import '../../domain/models/topology_snapshot.dart';

class BaselineStorageService {
  static const String baselineFileName = 'active_baseline_snapshot.json';

  static File getBaselineFile() {
    final dir = SharedDeviceDatabase.getDefaultDirectoryPath();
    return File(p.join(dir, baselineFileName));
  }

  static Future<void> saveBaseline(TopologySnapshot snapshot) async {
    try {
      final file = getBaselineFile();
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final jsonString = const JsonEncoder.withIndent('  ').convert(snapshot.toJson());
      await file.writeAsString(jsonString);
    } catch (_) {}
  }

  static Future<TopologySnapshot?> loadBaseline() async {
    try {
      final file = getBaselineFile();
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TopologySnapshot.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearBaseline() async {
    try {
      final file = getBaselineFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<String?> exportSnapshotToFile(TopologySnapshot snapshot) async {
    final jsonString = const JsonEncoder.withIndent('  ').convert(snapshot.toJson());
    final bytes = Uint8List.fromList(utf8.encode(jsonString));

    try {
      final safeName = snapshot.name
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final prefix = safeName.isEmpty ? 'baseline_snapshot' : safeName.toLowerCase();
      final timestamp = snapshot.createdAt
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final defaultName = '${prefix}_$timestamp.json';

      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export Baseline Topology Snapshot',
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

  static Future<TopologySnapshot?> importSnapshotFromFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Import Baseline Topology Snapshot',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (files.isEmpty) {
        return null;
      }

      final picked = files.first;
      String raw;
      try {
        final bytes = await picked.readAsBytes();
        raw = utf8.decode(bytes);
      } catch (_) {
        final path = picked.path;
        if (path == null) return null;
        raw = await File(path).readAsString();
      }

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          (decoded.containsKey('nodes') || decoded.containsKey('edges'))) {
        return TopologySnapshot.fromJson(decoded);
      }
    } catch (_) {}

    return null;
  }
}
