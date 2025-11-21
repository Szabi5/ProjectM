import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- Shared Data Model for Amortization Schedule ---
class YearlyScheduleRow {
  final int year;
  final double payment;
  final double principal;
  final double interest;
  final double balance;

  YearlyScheduleRow.fromJson(Map<String, dynamic> json)
      : year = json['year'] as int,
        payment = (json['payment'] as num).toDouble(),
        principal = (json['principal'] as num).toDouble(),
        interest = (json['interest'] as num).toDouble(),
        balance = (json['balance'] as num).toDouble();
}

/// A widget to display the yearly amortization schedule data in a table.
class AmortizationScheduleTable extends StatelessWidget {
  final List<YearlyScheduleRow> yearlySchedule;
  final String currencySymbol;
  final String title;

  const AmortizationScheduleTable({
    super.key,
    required this.yearlySchedule,
    required this.currencySymbol,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    if (yearlySchedule.isEmpty) {
      return Center(
        child: Text('No $title schedule data to display.'),
      );
    }

    final numberFormat = NumberFormat.currency(
      locale: 'en_US',
      symbol: currencySymbol,
      decimalDigits: 0,
    );

    // Build the list of data rows
    final dataRows = yearlySchedule.map((row) {
      return DataRow(
        cells: [
          DataCell(Text(row.year.toString())),
          DataCell(Text(numberFormat.format(row.payment))),
          DataCell(Text(numberFormat.format(row.principal))),
          DataCell(Text(numberFormat.format(row.interest))),
          DataCell(Text(numberFormat.format(row.balance))),
        ],
      );
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.symmetric(horizontal: 0),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              DataTable(
                columnSpacing: 20,
                headingRowColor: WidgetStateProperty.resolveWith((states) => Colors.grey.shade100),
                columns: const [
                  DataColumn(label: Text('Year', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Payment', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Principal', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Interest', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Balance', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: dataRows,
              ),
            ],
          ),
        ),
      ),
    );
  }
}