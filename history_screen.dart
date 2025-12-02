// lib/screens/history_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/history_service.dart'; 
import '../utils/pdf_generator.dart' as pdf_util; 

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _historyService = HistoryService();
  bool _isLoading = true;
  List<FinancialSnapshot> _history = [];

  // Formatters
  final gbpFormatter = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);
  final eurFormatter = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() { _isLoading = true; });
    final history = await _historyService.loadHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }
  
  Future<void> _exportHistoryPdf() async {
    if (_history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No history to export!'), backgroundColor: Colors.red),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      final pdfBytes = await pdf_util.generateHistoryReport(_history);
      pdf_util.viewPdf(context, pdfBytes, 'Financial_History_Report.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSnapshot(String yearMonth) async {
    final bool? didConfirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Snapshot"),
        content: Text("Are you sure you want to delete the snapshot for $yearMonth? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    
    if (didConfirm == true) {
      List<FinancialSnapshot> currentHistory = await _historyService.loadHistory();
      currentHistory.removeWhere((s) => s.yearMonth == yearMonth);
      
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList = currentHistory.map((s) => s.toJson()).toList();
      await prefs.setString('financial_history_snapshots', jsonEncode(jsonList));
      
      _loadHistory(); 
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Financial History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Export History PDF",
            onPressed: _exportHistoryPdf,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      "No history saved yet.\n\nGo to the 'Snapshot' tab and tap 'Save Monthly History' to start.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final snapshot = _history[index];
                    return _buildHistoryTile(snapshot);
                  },
                ),
    );
  }

  Widget _buildHistoryTile(FinancialSnapshot snapshot) {
    final titleDate = DateFormat('MMMM yyyy').format(snapshot.savedDate);
    final surplusColor = snapshot.monthlySurplus >= 0 ? Colors.green.shade600 : Colors.red.shade600;
    
    // Count how many details are stored in the new lists
    final budgetCount = snapshot.budgetItems.length;
    final savingsCount = snapshot.savingsPlatforms.length;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text(titleDate, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Text(
          "Net Worth: ${gbpFormatter.format(snapshot.netWorth)}",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _deleteSnapshot(snapshot.yearMonth),
          tooltip: "Delete Snapshot",
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader("Cash Flow", Icons.sync_alt, Colors.blue),
                _buildDetailRow("Monthly Income", gbpFormatter.format(snapshot.monthlyIncome)),
                _buildDetailRow("Monthly Expenses", gbpFormatter.format(snapshot.monthlyExpenses)),
                _buildDetailRow("Monthly Surplus", gbpFormatter.format(snapshot.monthlySurplus), color: surplusColor),
                
                if (snapshot.budgetItems.isNotEmpty)
                  _buildBudgetBreakdown(snapshot.budgetItems),

                _buildSectionHeader("Assets", Icons.add_circle, Colors.green),
                _buildDetailRow("EU Assets", gbpFormatter.format(snapshot.euAssetsGbp), originalValue: eurFormatter.format(snapshot.euAssetsEur)),
                _buildDetailRow("UK Assets", gbpFormatter.format(snapshot.ukAssetsGbp)),
                
                // --- SAVINGS BREAKDOWN ---
                if (snapshot.savingsPlatforms.isNotEmpty)
                  _buildSavingsBreakdown(snapshot.savingsPlatforms),

                const Divider(),
                _buildDetailRow("Total Assets", gbpFormatter.format(snapshot.totalAssetsGbp), isTotal: true),


                _buildSectionHeader("Liabilities", Icons.remove_circle, Colors.red),
                _buildDetailRow("EU Liabilities", gbpFormatter.format(snapshot.euLiabilitiesGbp), originalValue: eurFormatter.format(snapshot.euLiabilitiesEur)),
                _buildDetailRow("UK Liabilities", gbpFormatter.format(snapshot.ukLiabilitiesGbp)),
                _buildDetailRow("Total Liabilities", gbpFormatter.format(snapshot.totalLiabilitiesGbp), isTotal: true),
                
                _buildSectionHeader("Debt Balances", Icons.credit_card, Colors.grey),
                _buildDetailRow("UK Mortgage", gbpFormatter.format(snapshot.ukMortgageBalance)),
                _buildDetailRow("EU Mortgage", eurFormatter.format(snapshot.euMortgageBalance)),
                _buildDetailRow("Credit Cards", gbpFormatter.format(snapshot.creditCardBalance)),
              ],
            ),
          )
        ],
      ),
    );
  }
  
  // --- UPDATED HELPER: Lighter text color for dark mode ---
  Widget _buildSavingsBreakdown(List<dynamic> platforms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Text("Savings Breakdown:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
        ),
        ...platforms.map((p) {
          final name = p['name'] ?? 'Unknown';
          final currency = p['currency'] ?? 'GBP';
          final balance = (p['balance'] as num?)?.toDouble() ?? 0.0;
          final formatted = currency == 'EUR' 
              ? eurFormatter.format(balance) 
              : gbpFormatter.format(balance);

          return Padding(
            padding: const EdgeInsets.only(left: 12.0, bottom: 2.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // CHANGED: Colors.black54 -> Colors.white70 for dark mode visibility
                Text(name, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                Text(formatted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildBudgetBreakdown(List<dynamic> items) {
    int incomeCount = 0;
    int expenseCount = 0;
    
    for(var item in items) {
       if (item['type'].toString().contains('Income')) {
         incomeCount++;
       } else {
         expenseCount++;
       }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4.0, left: 12.0),
      child: Text(
        "Includes $incomeCount income items & $expenseCount expense items",
        style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {Color? color, String? originalValue, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label, 
              style: TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, fontSize: 15)
            )
          ),
          if (originalValue != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                "($originalValue)",
                style: const TextStyle(fontSize: 15, color: Colors.grey),
              ),
            ),
          Text(
            value, 
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)
          ),
        ],
      ),
    );
  }
}