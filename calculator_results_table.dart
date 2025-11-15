// lib/widgets/calculator_results_table.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // To format currency

// Define a simple class to hold the calculator results
class CalculatorResults {
  final double basePayment;
  final double targetPayment;
  final double requiredOverpayment;
  final double annualOverpayment;
  final double loanPctPerYear;
  final String capStatus;

  CalculatorResults({
    required this.basePayment,
    required this.targetPayment,
    required this.requiredOverpayment,
    required this.annualOverpayment,
    required this.loanPctPerYear,
    required this.capStatus,
  });

  factory CalculatorResults.fromJson(Map<String, dynamic> json) {
    return CalculatorResults(
      basePayment: (json['base_payment'] as num).toDouble(),
      targetPayment: (json['target_payment'] as num).toDouble(),
      requiredOverpayment: (json['required_overpayment'] as num).toDouble(),
      annualOverpayment: (json['annual_overpayment'] as num).toDouble(),
      loanPctPerYear: (json['loan_pct_per_year'] as num).toDouble(),
      capStatus: json['cap_status'] as String,
    );
  }
}

class CalculatorResultsTable extends StatelessWidget {
  final CalculatorResults results;
  final String currencySymbol;

  const CalculatorResultsTable({
    super.key,
    required this.results,
    required this.currencySymbol,
  });

  // Helper to format numbers as currency
  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_GB', // Use a locale that works well with currency symbols
      symbol: currencySymbol,
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  // Helper to format percentage
  String _formatPercent(double amount) {
    return NumberFormat.decimalPattern().format(amount) + '%';
  }

  // Creates a row for the result table
  TableRow _buildRow(String label, String value, {bool isHighlight = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isHighlight ? Colors.lightBlue.shade50 : null,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Text(
            label,
            style: TextStyle(fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(1.5),
          },
          children: [
            _buildRow('Current Base Monthly Payment', _formatCurrency(results.basePayment)),
            _buildRow(
              'Required Monthly Payment (for target years)', 
              _formatCurrency(results.targetPayment),
              isHighlight: true
            ),
            _buildRow(
              'Required Monthly Overpayment', 
              _formatCurrency(results.requiredOverpayment)
            ),
            _buildRow('Required Annual Overpayment', _formatCurrency(results.annualOverpayment)),
            _buildRow('Annual Overpayment as % of Loan', _formatPercent(results.loanPctPerYear)),
            _buildRow('Lump Sum Limits Status', results.capStatus),
          ],
        ),
      ),
    );
  }
}