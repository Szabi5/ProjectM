// lib/utils/csv_export.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Accepts a monthly or yearly schedule list (List<Map<String, dynamic>>)
/// and returns path to saved CSV file.
Future<String> exportScheduleToCsv(List<Map<String, dynamic>> schedule, {String filename = 'schedule.csv'}) async {
  if (schedule.isEmpty) {
    throw Exception('Schedule is empty');
  }

  // Determine columns from the first row (preserve ordering)
  final columns = schedule.first.keys.toList();
  final rows = <String>[];
  rows.add(columns.join(','));

  for (final row in schedule) {
    final values = columns.map((c) {
      final v = row[c];
      if (v == null) return '';
      // Escape quotes, commas, newlines
      final s = v.toString().replaceAll('"', '""');
      if (s.contains(',') || s.contains('\n') || s.contains('"')) {
        return '"$s"';
      }
      return s;
    }).toList();
    rows.add(values.join(','));
  }

  final csv = rows.join('\n');

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(csv, flush: true);

  return file.path;
}

/// Convenience: export and open share sheet
Future<void> exportAndShareSchedule(List<Map<String, dynamic>> schedule, {String filename = 'schedule.csv'}) async {
  final path = await exportScheduleToCsv(schedule, filename: filename);
  await Share.shareXFiles([XFile(path)], text: 'Mortgage schedule exported');
}