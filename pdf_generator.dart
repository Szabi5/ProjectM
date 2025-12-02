// lib/utils/pdf_generator.dart

import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart' show Colors, BuildContext;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

import '../models/report_data.dart'; 
import '../models/budget_report_data.dart';
import '../services/history_service.dart';

// Helper function to convert Hex string to PdfColor object
PdfColor colorFromHex(String hexColor) {
  final color = int.parse(hexColor.toUpperCase().replaceAll("#", "").substring(2), radix: 16);
  return PdfColor.fromInt(0xFF000000 | color);
}


Future<Uint8List> generateReport(ReportData data) async {
  
  final pw.Font helvetica = pw.Font.helvetica();
  final pw.Font helveticaBold = pw.Font.helveticaBold();
  
  final pw.ThemeData theme = pw.ThemeData.base().copyWith(
    defaultTextStyle: pw.TextStyle(font: helvetica, fontSize: 10),
    header1: pw.TextStyle(font: helveticaBold, fontSize: 14),
    header2: pw.TextStyle(font: helveticaBold, fontSize: 12),
  );

  final pdf = pw.Document(theme: theme);
  final reportSymbol = data.currencySymbol == '€' ? 'EUR' : data.currencySymbol;
  final numberFormat = NumberFormat.currency(symbol: reportSymbol, decimalDigits: 2);
  
  final List<List<String>> tableData = [
    ['Month', 'Payment', 'Principal', 'Interest', 'Balance'],
  ];
  
  data.monthlySchedule.take(60).map((row) => [
        row['month'].toString(),
        numberFormat.format(row['payment']),
        numberFormat.format(row['principal']),
        numberFormat.format(row['interest']),
        numberFormat.format(row['balance']),
      ]).forEach((row) => tableData.add(row));

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (pw.Context context) {
        return pw.Header(
          level: 0,
          child: pw.Text(
            data.reportTitle,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(Colors.blue.shade700.value), font: helveticaBold),
          ),
        );
      },
      build: (pw.Context context) => [
        pw.Header(level: 1, child: pw.Text("1. Summary of Projection", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.Paragraph(text: "Generated on ${DateFormat('yyyy-MM-dd').format(DateTime.now())}"),
        pw.SizedBox(height: 10),
        _buildSummaryRow("Base Monthly Payment", numberFormat.format(data.summary['base_monthly_payment'] ?? 0.0)),
        _buildSummaryRow("Total Monthly Payment", numberFormat.format(data.summary['overpay_monthly_payment'] ?? 0.0)),
        _buildSummaryRow("Time Saved", "${(data.summary['time_saved_years'] ?? 0.0).toStringAsFixed(1)} years"),
        pw.SizedBox(height: 10),

        pw.Header(level: 1, child: pw.Text("2. Amortization Schedule (First 5 Years)", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.Table.fromTextArray(
          headers: tableData[0],
          data: tableData.skip(1).toList(),
          cellStyle: pw.TextStyle(fontSize: 9, font: helvetica), 
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: helveticaBold),
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey500),
          headerAlignment: pw.Alignment.center,
          cellAlignment: pw.Alignment.centerRight,
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(2.5),
          }
        ),

        pw.SizedBox(height: 20),
        
        pw.Header(level: 1, child: pw.Text("3. Financial Impact", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        _buildSummaryRow("Total Interest Paid (Baseline)", numberFormat.format(data.summary['baseline_interest'] ?? 0.0)),
        _buildSummaryRow("Total Interest Paid (With Overpayment)", numberFormat.format(data.summary['overpay_interest'] ?? 0.0), highlight: true),
        _buildSummaryRow("Total Interest Saved", numberFormat.format(data.summary['interest_saved'] ?? 0.0), highlight: true),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _buildSummaryRow(String label, String value, {PdfColor? color, bool highlight = false}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: color ?? (highlight ? PdfColors.blue800 : PdfColors.black))),
      ],
    ),
  );
}

void viewPdf(BuildContext context, Uint8List pdfBytes, String filename) {
  Printing.sharePdf(bytes: pdfBytes, filename: filename);
}

// -------------------------------------------------------------------------
// BUDGET REPORT GENERATOR
// -------------------------------------------------------------------------

Future<Uint8List> generateBudgetReport(BudgetReportData data) async {
  final pw.Font helvetica = pw.Font.helvetica();
  final pw.Font helveticaBold = pw.Font.courierBold();
  
  final pw.ThemeData theme = pw.ThemeData.base().copyWith(
    defaultTextStyle: pw.TextStyle(font: helvetica, fontSize: 10),
    header1: pw.TextStyle(font: helveticaBold, fontSize: 14),
    header2: pw.TextStyle(font: helveticaBold, fontSize: 12),
  );

  final pdf = pw.Document(theme: theme);
  final gbpFormatter = NumberFormat.currency(symbol: '£', decimalDigits: 2);
  final eurFormatter = NumberFormat.currency(symbol: '€', decimalDigits: 2);

  final incomeRecords = data.records.where((r) => r['type'] == 'Income').toList();
  final expenseRecords = data.records.where((r) => r['type'] == 'Expense').toList();
  final categoryMap = {for (var c in data.categories) c['name']: colorFromHex(c['colorHex'])};

  pw.Widget buildBudgetCategoryTable(List<Map<String, dynamic>> records, String typeTitle) {
    final grouped = records.groupListsBy((r) => r['categoryName'] as String);
    final List<pw.Widget> categorySections = [];
    
    grouped.forEach((categoryName, items) {
      final categoryTotal = items.fold(0.0, (sum, item) => sum + (item['amount'] as double));
      final categoryColor = categoryMap[categoryName] ?? PdfColors.grey700;
      final currency = items.first['currency'] == 'EUR' ? eurFormatter : gbpFormatter;
      
      categorySections.add(
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          color: categoryColor.shade(0.1),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(categoryName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: helveticaBold, color: categoryColor)),
              pw.Text(currency.format(categoryTotal), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: helveticaBold, color: categoryColor)),
            ],
          ),
        ),
      );
      
      final itemRows = items.map((item) => [
        item['name'] as String,
        currency.format(item['amount'] as double),
        item['frequency'] as String,
      ]).toList();

      categorySections.add(
        pw.Table.fromTextArray(
          headers: ['Item Name', 'Amount', 'Frequency'],
          data: itemRows,
          cellStyle: pw.TextStyle(fontSize: 9, font: helvetica),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, font: helveticaBold, color: PdfColors.black),
          border: null,
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1.5),
            2: const pw.FlexColumnWidth(1),
          },
        )
      );
      categorySections.add(pw.SizedBox(height: 5)); 
    });
    
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Header(level: 1, child: pw.Text(typeTitle)),
        ...categorySections
    ]);
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (pw.Context context) {
        return pw.Header(
          level: 0,
          child: pw.Text(data.reportTitle, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        );
      },
      build: (pw.Context context) => [
        pw.Header(level: 1, child: pw.Text("1. Cash Flow Summary (GBP)")),
        _buildSummaryRow("Total Monthly Income", gbpFormatter.format(data.summary['totalMonthlyIncome']), highlight: true),
        _buildSummaryRow("Total Monthly Expenses", gbpFormatter.format(data.summary['totalMonthlyExpenses']), highlight: true),
        _buildSummaryRow("Monthly Surplus/Deficit", gbpFormatter.format(data.summary['monthlySurplus']), color: data.summary['monthlySurplus'] >= 0 ? PdfColors.green800 : PdfColors.red800),
        pw.SizedBox(height: 15),
        buildBudgetCategoryTable(incomeRecords, "2. Income Breakdown"),
        pw.SizedBox(height: 15),
        buildBudgetCategoryTable(expenseRecords, "3. Expense Breakdown"),
        pw.Paragraph(text: "Report Date: ${data.summary['reportDate']}", style: const pw.TextStyle(fontSize: 8)),
      ],
    ),
  );

  return pdf.save();
}

// -------------------------------------------------------------------------
// NEW: HISTORY REPORT GENERATOR
// -------------------------------------------------------------------------

Future<Uint8List> generateHistoryReport(List<FinancialSnapshot> history) async {
  
  final pw.Font helvetica = pw.Font.helvetica();
  final pw.Font helveticaBold = pw.Font.helveticaBold();
  
  final pw.ThemeData theme = pw.ThemeData.base().copyWith(
    defaultTextStyle: pw.TextStyle(font: helvetica, fontSize: 9),
    header1: pw.TextStyle(font: helveticaBold, fontSize: 16),
    header2: pw.TextStyle(font: helveticaBold, fontSize: 12),
  );

  final pdf = pw.Document(theme: theme);
  final gbp = NumberFormat.currency(symbol: '£', decimalDigits: 0);
  final eur = NumberFormat.currency(symbol: '€', decimalDigits: 0);

  // Table Data Structure
  final List<List<String>> tableData = [
    ['Month', 'Net Worth', 'Assets', 'Liabilities', 'Income', 'Expense', 'Surplus'], // Header
  ];

  for (var snap in history) {
    tableData.add([
      snap.yearMonth,
      gbp.format(snap.netWorth),
      gbp.format(snap.totalAssetsGbp),
      gbp.format(snap.totalLiabilitiesGbp),
      gbp.format(snap.monthlyIncome),
      gbp.format(snap.monthlyExpenses),
      gbp.format(snap.monthlySurplus),
    ]);
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (pw.Context context) {
        return pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Financial History Report", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text("Generated: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10)),
            ]
          )
        );
      },
      build: (pw.Context context) {
        final List<pw.Widget> content = [
          pw.SizedBox(height: 10),
          // Main History Table
          pw.Table.fromTextArray(
            headers: tableData[0],
            data: tableData.skip(1).toList(),
            cellStyle: pw.TextStyle(fontSize: 10, font: helvetica), 
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, font: helveticaBold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerRight,
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2), // Month
              1: const pw.FlexColumnWidth(1.5), // Net Worth
              2: const pw.FlexColumnWidth(1.5), // Assets
              3: const pw.FlexColumnWidth(1.5), // Liabilities
              4: const pw.FlexColumnWidth(1.2), // Income
              5: const pw.FlexColumnWidth(1.2), // Expense
              6: const pw.FlexColumnWidth(1.2), // Surplus
            }
          ),
          pw.SizedBox(height: 20),
          pw.Header(level: 1, child: pw.Text("Detailed Savings History", style: pw.TextStyle(fontSize: 14))),
          pw.Divider(),
        ];
        
        // --- NEW: Detailed Savings Breakdown Loop ---
        for (var snap in history) {
          if (snap.savingsPlatforms.isNotEmpty) {
             final savingsRows = snap.savingsPlatforms.map((p) {
                final balance = (p['balance'] as num?)?.toDouble() ?? 0.0;
                final symbol = p['currency'] == 'EUR' ? eur : gbp;
                return [p['name'] ?? '', symbol.format(balance)];
             }).toList();

             content.add(
               pw.Column(
                 crossAxisAlignment: pw.CrossAxisAlignment.start,
                 children: [
                   pw.SizedBox(height: 10),
                   pw.Text(snap.yearMonth, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                   pw.SizedBox(height: 4),
                   pw.Table.fromTextArray(
                      headers: ['Platform', 'Balance'],
                      data: savingsRows,
                      cellStyle: pw.TextStyle(fontSize: 9),
                      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      border: pw.TableBorder.all(color: PdfColors.grey300),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(3),
                        1: const pw.FlexColumnWidth(1),
                      }
                   )
                 ]
               )
             );
          }
        }

        return content;
      },
    ),
  );

  return pdf.save();
}