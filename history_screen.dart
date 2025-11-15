// lib/screens/history_screen.dart
//
// UPDATED:
// - Added missing imports for 'dart:convert' and 'shared_preferences'.
// - Fixed the _deleteSnapshot function to correctly remove items from storage.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert'; // <-- FIX 1: Added missing import
import 'package:shared_preferences/shared_preferences.dart'; // <-- FIX 2: Added missing import
import '../services/history_service.dart'; 

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
  
  //
  // --- FIX 3: Rewrote the _deleteSnapshot function ---
  //
  Future<void> _deleteSnapshot(String yearMonth) async {
     // Show a confirmation dialog first
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
      // Load the current history
      List<FinancialSnapshot> currentHistory = await _historyService.loadHistory();
      
      // Remove the one we want to delete
      currentHistory.removeWhere((s) => s.yearMonth == yearMonth);
      
      // Re-save the modified list back to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList = currentHistory.map((s) => s.toJson()).toList();
      await prefs.setString('financial_history_snapshots', jsonEncode(jsonList));
      
      // Reload the UI to show the change
      _loadHistory(); 
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Financial History"),
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
    // Format the date for the title
    final titleDate = DateFormat('MMMM yyyy').format(snapshot.savedDate);
    final surplusColor = snapshot.monthlySurplus >= 0 ? Colors.green.shade600 : Colors.red.shade600;
    
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
              children: [
                // --- Cash Flow ---
                _buildSectionHeader("Cash Flow", Icons.sync_alt, Colors.blue),
                _buildDetailRow("Monthly Income", gbpFormatter.format(snapshot.monthlyIncome)),
                _buildDetailRow("Monthly Expenses", gbpFormatter.format(snapshot.monthlyExpenses)),
                _buildDetailRow("Monthly Surplus", gbpFormatter.format(snapshot.monthlySurplus), color: surplusColor),
                
                // --- Assets ---
                _buildSectionHeader("Assets", Icons.add_circle, Colors.green),
                _buildDetailRow("EU Assets", gbpFormatter.format(snapshot.euAssetsGbp), originalValue: eurFormatter.format(snapshot.euAssetsEur)),
                _buildDetailRow("UK Assets", gbpFormatter.format(snapshot.ukAssetsGbp)),
                _buildDetailRow("Total Assets", gbpFormatter.format(snapshot.totalAssetsGbp), isTotal: true),

                // --- Liabilities ---
                _buildSectionHeader("Liabilities", Icons.remove_circle, Colors.red),
                _buildDetailRow("EU Liabilities", gbpFormatter.format(snapshot.euLiabilitiesGbp), originalValue: eurFormatter.format(snapshot.euLiabilitiesEur)),
                _buildDetailRow("UK Liabilities", gbpFormatter.format(snapshot.ukLiabilitiesGbp)),
                _buildDetailRow("Total Liabilities", gbpFormatter.format(snapshot.totalLiabilitiesGbp), isTotal: true),
                
                // --- Raw Balances ---
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