// lib/utils/rollover_export.dart
// Helper functions to export the rollover Excel from the Python server.
// - exportAndSaveRolloverExcel saves the returned .xlsx to the user's Downloads (or a fallback dir) and returns the saved path.
// - exportAndShareRolloverExcel saves then opens the native share sheet.
//
// Requires:
//   path_provider, share_plus
// Optionally for "open file" UI action use open_file (shown in rollover_tab changes).

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/python_bridge.dart';

Future<String> _getBestDownloadsPath(String filename) async {
  try {
    // Prefer the OS Downloads folder when available
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return '${downloads.path}/$filename';
    }
  } catch (_) {
    // ignore and fallback
  }

  // Fallback to application documents directory (always available)
  final docs = await getApplicationDocumentsDirectory();
  return '${docs.path}/$filename';
}

/// Calls the Python API with script "Export rollover to excel" and payload (same payload you pass for rollover).
/// Saves the returned base64 Excel file to Downloads (or fallback) and returns the saved file path.
Future<String> exportAndSaveRolloverExcel(FlutterPythonBridge bridge, Map<String, dynamic> payload) async {
  final resString = await bridge.run("Export rollover to excel", payload);
  final Map<String, dynamic> res = jsonDecode(resString) as Map<String, dynamic>;

  if (res.containsKey('error')) {
    throw Exception('Export error: ${res['error']}');
  }
  if (!res.containsKey('excel_base64')) {
    throw Exception('No excel payload returned from server');
  }

  final String b64 = res['excel_base64'] as String;
  final bytes = base64Decode(b64);
  final filename = res['filename'] as String? ?? 'rollover_analysis.xlsx';
  final path = await _getBestDownloadsPath(filename);

  final file = File(path);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);

  return path;
}

/// Convenience: export, save to downloads, then open native share sheet.
Future<String> exportAndShareRolloverExcel(FlutterPythonBridge bridge, Map<String, dynamic> payload) async {
  final savedPath = await exportAndSaveRolloverExcel(bridge, payload);
  await Share.shareXFiles([XFile(savedPath)], text: 'Rollover analysis exported');
  return savedPath;
}