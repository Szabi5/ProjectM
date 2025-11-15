// lib/screens/savings_management_screen.dart
//
// UPDATED:
// - Added a real-time summary card at the top.
// - Loads the EUR/GBP conversion rate from SharedPreferences.
// - Summary updates automatically as you type.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/savings_service.dart'; // Import our new service

class SavingsManagementScreen extends StatefulWidget {
  const SavingsManagementScreen({Key? key}) : super(key: key);

  @override
  State<SavingsManagementScreen> createState() => _SavingsManagementScreenState();
}

class _SavingsManagementScreenState extends State<SavingsManagementScreen> {
  final _service = SavingsService();
  bool _isLoading = true;
  List<SavingsPlatform> _platforms = [];
  
  // We need a map of controllers to store the text field values
  Map<String, TextEditingController> _balanceControllers = {};
  
  // --- NEW: Controller for conversion rate ---
  final _conversionRateController = TextEditingController(text: "0.85");

  // --- NEW: State variables for the summary ---
  double _totalEuSavings = 0.0;
  double _totalGbpSavings = 0.0;
  double _totalCombinedGbp = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    // Clean up all the controllers
    _balanceControllers.values.forEach((controller) => controller.dispose());
    _conversionRateController.dispose();
    super.dispose();
  }
  
  void _addListeners() {
    _conversionRateController.addListener(_calculateSummary);
    _balanceControllers.values.forEach((controller) {
      controller.addListener(_calculateSummary);
    });
  }

  void _removeListeners() {
     _conversionRateController.removeListener(_calculateSummary);
    _balanceControllers.values.forEach((controller) {
      controller.removeListener(_calculateSummary);
    });
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; });
    _removeListeners(); // Stop listeners while we reset controllers

    final prefs = await SharedPreferences.getInstance();
    final platforms = await _service.loadPlatforms();
    
    // Load the saved conversion rate
    _conversionRateController.text = prefs.getString('snapshot_conversion_rate') ?? '0.85';

    // Clear old controllers and create new ones
    _balanceControllers.values.forEach((controller) => controller.dispose());
    _balanceControllers = {
      for (var p in platforms)
        p.id: TextEditingController(text: p.balance.toStringAsFixed(2))
    };

    setState(() {
      _platforms = platforms;
      _isLoading = false;
    });
    
    _calculateSummary(); // Calculate totals *after* setting controllers
    _addListeners(); // Add listeners back for real-time updates
  }

  Future<void> _saveData() async {
    _removeListeners(); // Stop listeners while saving
    
    // Update the balance in our model from the text controller
    for (var platform in _platforms) {
      final balanceText = _balanceControllers[platform.id]?.text ?? '0';
      platform.balance = double.tryParse(balanceText) ?? 0.0;
    }
    
    // Save the entire updated list
    await _service.savePlatforms(_platforms);
    
    // Also save the conversion rate if it was changed here
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('snapshot_conversion_rate', _conversionRateController.text);
    
    _addListeners(); // Re-apply listeners

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Savings saved!'), backgroundColor: Colors.green),
    );
  }

  // --- NEW: Calculates summary totals from controllers ---
  void _calculateSummary() {
    double tempEuTotal = 0.0;
    double tempGbpTotal = 0.0;
    final double rate = double.tryParse(_conversionRateController.text) ?? 0.85;

    for (var platform in _platforms) {
      final balance = double.tryParse(_balanceControllers[platform.id]?.text ?? '0') ?? 0.0;
      if (platform.currency == "EUR") {
        tempEuTotal += balance;
      } else {
        tempGbpTotal += balance;
      }
    }
    
    setState(() {
      _totalEuSavings = tempEuTotal;
      _totalGbpSavings = tempGbpTotal;
      _totalCombinedGbp = tempGbpTotal + (tempEuTotal * rate);
    });
  }


  void _showAddPlatformDialog() {
    final nameController = TextEditingController();
    String selectedCurrency = "GBP"; // Default
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder( 
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add New Platform"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Platform Name (e.g., Wise)"),
                    autofocus: true,
                  ),
                  DropdownButton<String>(
                    value: selectedCurrency,
                    items: [
                      const DropdownMenuItem(value: "GBP", child: Text("GBP (£)")),
                      const DropdownMenuItem(value: "EUR", child: Text("EUR (€)")),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() { 
                          selectedCurrency = value;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text;
                    if (name.isNotEmpty) {
                      final newPlatform = _service.createNewPlatform(name, selectedCurrency);
                      _platforms.add(newPlatform); // Add to list
                      await _service.savePlatforms(_platforms); // Save immediately
                      Navigator.of(context).pop();
                      _loadData(); // Reload all data to add new controller/listener
                    }
                  },
                  child: const Text("Add"),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _deletePlatform(String id) async {
    _platforms.removeWhere((p) => p.id == id);
    // Remove and dispose the controller
    _balanceControllers.remove(id)?.dispose();
    await _service.savePlatforms(_platforms); // Save immediately
    _loadData(); // Reload to recalculate summary
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Savings"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveData,
            tooltip: "Save Savings",
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView( // Use CustomScrollView to mix list and other widgets
              slivers: [
                // --- NEW: Summary Card ---
                SliverToBoxAdapter(
                  child: _buildSummaryCard(),
                ),
                
                // --- List of Platforms ---
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final platform = _platforms[index];
                      final controller = _balanceControllers[platform.id];
                      final String prefix = platform.currency == "GBP" ? "£" : "€";

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
                        child: ListTile(
                          title: Text(platform.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: TextFormField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: "Current Balance",
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Text(prefix, style: const TextStyle(fontSize: 16)),
                                ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deletePlatform(platform.id),
                          ),
                        ),
                      );
                    },
                    childCount: _platforms.length,
                  ),
                ),
                
                // --- NEW: Settings Card ---
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                    child: Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Settings", style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _conversionRateController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "EUR→GBP Conversion Rate",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPlatformDialog,
        child: const Icon(Icons.add),
        tooltip: "Add New Platform",
      ),
    );
  }

  // --- NEW: Summary Card Widget ---
  Widget _buildSummaryCard() {
    final gbpFormatter = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);
    final eurFormatter = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
    final double rate = double.tryParse(_conversionRateController.text) ?? 0.85;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(12.0),
      color: Colors.deepPurple.shade700,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "TOTAL SAVINGS (GBP)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              gbpFormatter.format(_totalCombinedGbp),
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const Divider(color: Colors.white30, height: 24),
            _buildLegendItem(
              Colors.green.shade300, 
              "UK Savings (GBP)", 
              gbpFormatter.format(_totalGbpSavings)
            ),
            _buildLegendItem(
              Colors.green.shade600, 
              "EU Savings (EUR)", 
              gbpFormatter.format(_totalEuSavings * rate), // Converted value
              originalValue: eurFormatter.format(_totalEuSavings) // Original value
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW: Legend Item Widget (from Snapshot tab) ---
  Widget _buildLegendItem(Color color, String title, String gbpValue, {String? originalValue}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(width: 16, height: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, color: Colors.white)),
          ),
          if (originalValue != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                "($originalValue)",
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
            ),
          Text(
            gbpValue,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}