// lib/utils/refinance_export.dart
// Helper to request a refinance Excel from Python, save it to disk (Downloads or app documents) and optionally share/open it.
//
// Usage:
//  final savedPath = await exportAndSaveRefinanceExcel(bridge, payload);
//  or
//  final savedPath = await exportAndShareRefinanceExcel(bridge, payload);

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/python_bridge.dart';

Future<String> _getBestDownloadsPath(String filename) async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return '${downloads.path}/$filename';
  } catch (_) {}
  final docs = await getApplicationDocumentsDirectory();
  return '${docs.path}/$filename';
}

Future<String> exportAndSaveRefinanceExcel(FlutterPythonBridge bridge, Map<String, dynamic> payload) async {
  final resString = await bridge.run("Export refinance to excel", payload);
  final Map<String, dynamic> res = jsonDecode(resString) as Map<String, dynamic>;

  if (res.containsKey('error')) throw Exception('Export error: ${res['error']}');
  if (!res.containsKey('excel_base64')) throw Exception('No excel payload returned from server');

  final String b64 = res['excel_base64'] as String;
  final bytes = base64Decode(b64);
  final filename = res['filename'] as String? ?? 'refinance_analysis.xlsx';
  final path = await _getBestDownloadsPath(filename);
  final file = File(path);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return path;
}

Future<String> exportAndShareRefinanceExcel(FlutterPythonBridge bridge, Map<String, dynamic> payload) async {
  final path = await exportAndSaveRefinanceExcel(bridge, payload);
  await Share.shareXFiles([XFile(path)], text: 'Refinance analysis exported');
  return path;
}