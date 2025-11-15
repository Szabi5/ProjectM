// lib/screens/budget_management_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/budget_service.dart'; // Import our new service

class BudgetManagementScreen extends StatefulWidget {
  const BudgetManagementScreen({Key? key}) : super(key: key);

  @override
  State<BudgetManagementScreen> createState() => _BudgetManagementScreenState();
}

class _BudgetManagementScreenState extends State<BudgetManagementScreen> {
  final _service = BudgetService();
  bool _isLoading = true;
  List<BudgetItem> _items = [];
  Map<String, TextEditingController> _amountControllers = {};
  
  // State for the summary card
  double _totalMonthlyIncome = 0.0;
  double _totalMonthlyExpenses = 0.0;
  double _monthlySurplus = 0.0;
  final _conversionRateController = TextEditingController(text: "0.85");


  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountControllers.values.forEach((controller) => controller.dispose());
    _conversionRateController.dispose();
    super.dispose();
  }
  
  void _addListeners() {
    _conversionRateController.addListener(_calculateSummary);
    _amountControllers.values.forEach((controller) {
      controller.addListener(_calculateSummary);
    });
  }

  void _removeListeners() {
    _conversionRateController.removeListener(_calculateSummary);
    _amountControllers.values.forEach((controller) {
      controller.removeListener(_calculateSummary);
    });
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; });
    _removeListeners(); 

    final items = await _service.loadItems();
    
    // Also load the conversion rate from the Snapshot tab's prefs
    // (We use a local controller for real-time calcs)
    // final prefs = await SharedPreferences.getInstance(); 
    // _conversionRateController.text = prefs.getString('snapshot_conversion_rate') ?? '0.85';

    _amountControllers.values.forEach((controller) => controller.dispose());
    _amountControllers = {
      for (var i in items)
        i.id: TextEditingController(text: i.amount.toStringAsFixed(2))
    };

    setState(() {
      _items = items;
      _isLoading = false;
    });
    
    _calculateSummary(); 
    _addListeners(); 
  }

  Future<void> _saveData() async {
    _removeListeners(); 
    
    for (var item in _items) {
      final amountText = _amountControllers[item.id]?.text ?? '0';
      item.amount = double.tryParse(amountText) ?? 0.0;
    }
    
    await _service.saveItems(_items);
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.setString('snapshot_conversion_rate', _conversionRateController.text);
    
    _addListeners(); 

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Budget items saved!'), backgroundColor: Colors.green),
    );
  }

  // --- Calculates summary totals from controllers ---
  void _calculateSummary() {
    double tempMonthlyIncome = 0.0;
    double tempMonthlyExpenses = 0.0;
    final double rate = double.tryParse(_conversionRateController.text) ?? 0.85;

    for (var item in _items) {
      double amount = double.tryParse(_amountControllers[item.id]?.text ?? '0') ?? 0.0;
      
      // Convert to GBP if needed
      if (item.currency == "EUR") {
        amount = amount * rate;
      }
      
      // Convert to Monthly if needed
      if (item.frequency == BudgetFrequency.Weekly) {
        amount = amount * 4.3333; // Avg weeks in a month
      }

      if (item.type == BudgetItemType.Income) {
        tempMonthlyIncome += amount;
      } else {
        tempMonthlyExpenses += amount;
      }
    }
    
    setState(() {
      _totalMonthlyIncome = tempMonthlyIncome;
      _totalMonthlyExpenses = tempMonthlyExpenses;
      _monthlySurplus = tempMonthlyIncome - tempMonthlyExpenses;
    });
  }


  void _showAddItemDialog() {
    final nameController = TextEditingController();
    String selectedCurrency = "GBP"; 
    BudgetItemType selectedType = BudgetItemType.Expense;
    BudgetFrequency selectedFrequency = BudgetFrequency.Monthly;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder( 
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add New Item"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: "Item Name (e.g., Salary, Netflix)"),
                      autofocus: true,
                    ),
                    // --- Type Picker ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Type:"),
                        Radio<BudgetItemType>(
                          value: BudgetItemType.Income,
                          groupValue: selectedType,
                          onChanged: (val) => setDialogState(() => selectedType = val!),
                        ),
                        const Text("Income"),
                        Radio<BudgetItemType>(
                          value: BudgetItemType.Expense,
                          groupValue: selectedType,
                          onChanged: (val) => setDialogState(() => selectedType = val!),
                        ),
                        const Text("Expense"),
                      ],
                    ),
                    // --- Currency Picker ---
                    DropdownButton<String>(
                      value: selectedCurrency,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: "GBP", child: Text("Currency: GBP (£)")),
                        const DropdownMenuItem(value: "EUR", child: Text("Currency: EUR (€)")),
                      ],
                      onChanged: (value) => setDialogState(() => selectedCurrency = value!),
                    ),
                    // --- Frequency Picker ---
                    DropdownButton<BudgetFrequency>(
                      value: selectedFrequency,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: BudgetFrequency.Monthly, child: Text("Frequency: Monthly")),
                        const DropdownMenuItem(value: BudgetFrequency.Weekly, child: Text("Frequency: Weekly")),
                      ],
                      onChanged: (value) => setDialogState(() => selectedFrequency = value!),
                    ),
                  ],
                ),
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
                      final newItem = _service.createNewItem(name, selectedCurrency, selectedType, selectedFrequency);
                      _items.add(newItem); 
                      await _service.saveItems(_items); 
                      Navigator.of(context).pop();
                      _loadData(); 
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

  void _deleteItem(String id) async {
    _items.removeWhere((p) => p.id == id);
    _amountControllers.remove(id)?.dispose();
    await _service.saveItems(_items); 
    _loadData(); // Reload to recalculate summary
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Income & Expenses"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveData,
            tooltip: "Save Budget",
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView( 
              slivers: [
                // --- Summary Card ---
                SliverToBoxAdapter(
                  child: _buildSummaryCard(),
                ),
                
                // --- List of Budget Items ---
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _items[index];
                      final controller = _amountControllers[item.id];
                      final String prefix = item.currency == "GBP" ? "£" : "€";
                      final Color color = item.type == BudgetItemType.Income ? Colors.green : Colors.red;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
                        child: ListTile(
                          leading: Icon(
                            item.type == BudgetItemType.Income ? Icons.arrow_upward : Icons.arrow_downward,
                            color: color,
                          ),
                          title: Text(item.name, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: TextFormField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: "${item.frequency == BudgetFrequency.Weekly ? 'Weekly' : 'Monthly'} Amount",
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
                            icon: const Icon(Icons.delete_outline, color: Colors.grey),
                            onPressed: () => _deleteItem(item.id),
                          ),
                        ),
                      );
                    },
                    childCount: _items.length,
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddItemDialog,
        child: const Icon(Icons.add),
        tooltip: "Add New Item",
      ),
    );
  }

  Widget _buildSummaryCard() {
    final gbpFormatter = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);
    final surplusColor = _monthlySurplus >= 0 ? Colors.green.shade600 : Colors.red.shade600;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(12.0),
      color: Colors.blueGrey.shade800,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "MONTHLY CASH FLOW (GBP)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              gbpFormatter.format(_monthlySurplus),
              style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: surplusColor),
            ),
            const Divider(color: Colors.white30, height: 24),
            _buildLegendItem(
              Colors.green.shade300, 
              "Total Income", 
              gbpFormatter.format(_totalMonthlyIncome)
            ),
            _buildLegendItem(
              Colors.red.shade300, 
              "Total Expenses", 
              gbpFormatter.format(_totalMonthlyExpenses)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(width: 16, height: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, color: Colors.white)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}