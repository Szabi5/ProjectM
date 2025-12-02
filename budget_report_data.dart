// lib/models/budget_report_data.dart

import 'dart:core';

/// Defines the structured data passed to the Budget PDF Generator.
class BudgetReportData {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> records; // Detailed item records
  final List<Map<String, dynamic>> categories; // Category list with colors/types
  final String reportTitle;

  BudgetReportData({
    required this.summary,
    required this.records,
    required this.categories,
    required this.reportTitle,
  });
}