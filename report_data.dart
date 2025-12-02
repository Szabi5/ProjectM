// lib/models/report_data.dart

import 'dart:core'; // Ensure core types are available

/// Defines the structure of data needed for the PDF report.
class ReportData {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> monthlySchedule;
  final String currencySymbol;
  final String reportTitle;

  ReportData({
    required this.summary,
    required this.monthlySchedule,
    required this.currencySymbol,
    required this.reportTitle,
  });
}