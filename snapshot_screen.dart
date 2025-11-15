// lib/screens/snapshot_screen.dart
//
// UPDATED:
// - Added HistoryService.
// - Added new "Save Monthly History" button.
// - This button saves a full snapshot of all calculated data.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/savings_service.dart'; 
import '../services/budget_service.dart';
import '../services/history_service.dart'; // <-- 1. IMPORT NEW SERVICE

class SnapshotScreen extends StatefulWidget {
  const SnapshotScreen({Key? key}) : super(key: key);

  @override
  State<SnapshotScreen> createState() => _SnapshotScreenState();
}

class _SnapshotScreenState extends State<SnapshotScreen> {
  // --- State Variables ---
  double _totalAssets = 0.0;
  double _totalLiabilities = 0.0;
  double _netWorth = 0.0;
  bool _isLoading = true;

  double _euAssetsGbp = 0.0;
  double _ukAssetsGbp = 0.0;
  double _euLiabilitiesGbp = 0.0;
  double _ukLiabilitiesGbp = 0.0;
  
  double _euAssetsEur = 0.0;
  double _euLiabilitiesEur = 0.0;
  
  double _totalMonthlyIncome = 0.0;
  double _totalMonthlyExpenses = 0.0;
  double _monthlySurplus = 0.0;

  List<SavingsPlatform> _loadedPlatforms = [];
  List<BudgetItem> _loadedBudgetItems = []; 

  // --- Controllers ---
  final _euPropertyController = TextEditingController();
  final _ukPropertyController = TextEditingController();
  final _euDebtController = TextEditingController();
  final _ukDebtController = TextEditingController();
  final _creditCardController = TextEditingController();
  final _conversionRateController = TextEditingController(text: "0.85");

  late final Map<String, TextEditingController> _controllers = {
    'snapshot_conversion_rate': _conversionRateController,
    'eu_mortgage_value': _euPropertyController, 
    'uk_mortgage_value': _ukPropertyController,
    'eu_mortgage_loan': _euDebtController,     
    'uk_mortgage_loan': _ukDebtController,     
    'debt_payoff_balance': _creditCardController,
  };
  
  final _savingsService = SavingsService();
  final _budgetService = BudgetService(); 
  final _historyService = HistoryService(); // <-- 2. ADD HISTORY SERVICE

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _removeListeners();
    _controllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  void _addListeners() {
    for (var controller in _controllers.values) {
      controller.addListener(_calculateSnapshot);
    }
  }

  void _removeListeners() {
    for (var controller in _controllers.values) {
      controller.removeListener(_calculateSnapshot);
    }
  }

  Future<void> _loadAllData() async {
    if (!_isLoading) {
      setState(() { _isLoading = true; });
    }
    _removeListeners(); 
    final prefs = await SharedPreferences.getInstance();
    
    final results = await Future.wait([
      _savingsService.loadPlatforms(),
      _budgetService.loadItems(),
    ]);
    _loadedPlatforms = results[0] as List<SavingsPlatform>;
    _loadedBudgetItems = results[1] as List<BudgetItem>;

    _controllers['snapshot_conversion_rate']?.text = prefs.getString('snapshot_conversion_rate') ?? '0.85';
    _controllers['eu_mortgage_value']?.text = prefs.getString('eu_mortgage_value') ?? '0';
    _controllers['uk_mortgage_value']?.text = prefs.getString('uk_mortgage_value') ?? '0';
    _controllers['eu_mortgage_loan']?.text = prefs.getString('eu_mortgage_loan') ?? '0';
    _controllers['uk_mortgage_loan']?.text = prefs.getString('uk_mortgage_loan') ?? '0';
    _controllers['debt_payoff_balance']?.text = prefs.getString('debt_payoff_balance') ?? '0';

    _calculateSnapshot();
    
    _addListeners(); 
    if(mounted) {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString('snapshot_conversion_rate', _conversionRateController.text);
    await prefs.setString('eu_mortgage_value', _euPropertyController.text);
    await prefs.setString('uk_mortgage_value', _ukPropertyController.text);
    await prefs.setString('eu_mortgage_loan', _euDebtController.text);
    await prefs.setString('uk_mortgage_loan', _ukDebtController.text);
    await prefs.setString('debt_payoff_balance', _creditCardController.text);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Snapshot saved!'), backgroundColor: Colors.green),
    );
  }
  
  // --- 3. NEW: Save to History Function ---
  Future<void> _saveToHistory() async {
    // Show a confirmation dialog first
    final bool? didConfirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save Monthly History"),
        content: Text("Save a snapshot for ${DateFormat('MMMM yyyy').format(DateTime.now())}? This will overwrite any existing snapshot for this month."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (didConfirm != true) {
      return; // User cancelled
    }
    
    // User confirmed, proceed to save
    setState(() { _isLoading = true; });

    try {
      // Get raw EUR balances for savings
      double euSavings = 0.0;
      double gbpSavings = 0.0;
      for (var p in _loadedPlatforms) {
        if (p.currency == "EUR") {
          euSavings += p.balance;
        } else {
          gbpSavings += p.balance;
        }
      }
      
      // Get raw debt balances
      final double euDebt = double.tryParse(_euDebtController.text) ?? 0.0;
      final double ukDebt = double.tryParse(_ukDebtController.text) ?? 0.0;
      final double ccDebt = double.tryParse(_creditCardController.text) ?? 0.0;

      // Create the snapshot object from current state
      final snapshot = FinancialSnapshot(
        yearMonth: DateFormat('yyyy-MM').format(DateTime.now()), 
        savedDate: DateTime.now(), 
        netWorth: _netWorth, 
        totalAssetsGbp: _totalAssets, 
        totalLiabilitiesGbp: _totalLiabilities, 
        euAssetsGbp: _euAssetsGbp, 
        ukAssetsGbp: _ukAssetsGbp, 
        euAssetsEur: _euAssetsEur, 
        euLiabilitiesGbp: _euLiabilitiesGbp, 
        ukLiabilitiesGbp: _ukLiabilitiesGbp, 
        euLiabilitiesEur: _euLiabilitiesEur, 
        euMortgageBalance: euDebt, 
        ukMortgageBalance: ukDebt, 
        creditCardBalance: ccDebt, 
        euSavings: euSavings, 
        gbpSavings: gbpSavings, 
        monthlyIncome: _totalMonthlyIncome, 
        monthlyExpenses: _totalMonthlyExpenses, 
        monthlySurplus: _monthlySurplus
      );

      // Save it
      await _historyService.saveSnapshot(snapshot);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📈 History snapshot saved!'), backgroundColor: Colors.deepPurple),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save history: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }


  void _calculateSnapshot() {
    double euSavings = 0.0;
    double gbpSavings = 0.0;
    for (var p in _loadedPlatforms) {
      if (p.currency == "EUR") {
        euSavings += p.balance;
      } else {
        gbpSavings += p.balance;
      }
    }

    final double euProperty = double.tryParse(_euPropertyController.text) ?? 0.0;
    final double ukProperty = double.tryParse(_ukPropertyController.text) ?? 0.0;
    
    final double euDebt = double.tryParse(_euDebtController.text) ?? 0.0;
    final double ukDebt = double.tryParse(_ukDebtController.text) ?? 0.0;
    final double ccDebt = double.tryParse(_creditCardController.text) ?? 0.0;
    
    final double rate = double.tryParse(_conversionRateController.text) ?? 0.85;

    final double euAssets = euProperty + euSavings; 
    final double euLiabilities = euDebt; 
    
    final double euAssetsGbp = euAssets * rate;
    final double ukAssetsGbp = ukProperty + gbpSavings;
    
    final double euLiabilitiesGbp = euLiabilities * rate;
    final double ukLiabilitiesGbp = ukDebt + ccDebt;

    final double totalAssets = euAssetsGbp + ukAssetsGbp;
    final double totalLiabilities = euLiabilitiesGbp + ukLiabilitiesGbp;
    final double netWorth = totalAssets - totalLiabilities;
    
    double tempMonthlyIncome = 0.0;
    double tempMonthlyExpenses = 0.0;
    for (var item in _loadedBudgetItems) {
      double amount = item.amount;
      if (item.currency == "EUR") {
        amount = amount * rate;
      }
      if (item.frequency == BudgetFrequency.Weekly) {
        amount = amount * 4.3333;
      }
      if (item.type == BudgetItemType.Income) {
        tempMonthlyIncome += amount;
      } else {
        tempMonthlyExpenses += amount;
      }
    }

    if (!mounted) return;
    setState(() {
      _totalAssets = totalAssets;
      _totalLiabilities = totalLiabilities;
      _netWorth = netWorth;
      _euAssetsGbp = euAssetsGbp;
      _ukAssetsGbp = ukAssetsGbp;
      _euLiabilitiesGbp = euLiabilitiesGbp;
      _ukLiabilitiesGbp = ukLiabilitiesGbp;
      _euAssetsEur = euAssets;
      _euLiabilitiesEur = euLiabilities;
      
      _totalMonthlyIncome = tempMonthlyIncome;
      _totalMonthlyExpenses = tempMonthlyExpenses;
      _monthlySurplus = tempMonthlyIncome - tempMonthlyExpenses;
    });
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("Your Financial Snapshot", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Divider(height: 20),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _buildSummaryCard(formatter),
                  _buildCashflowCard(formatter),
                  _buildPieChart(formatter),
                ],
                
                _buildSectionHeader("Assets (What you Own)", Icons.add_circle, Colors.green),
                _buildInputCard([
                  _buildTextField(_ukPropertyController, 'UK Property Value', '£'),
                  _buildTextField(_euPropertyController, 'EU Property Value', '€'),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "Savings & Investments are managed via the 💰 icon in the app bar. Press Refresh to update.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                ]),

                _buildSectionHeader("Liabilities (What you Owe)", Icons.remove_circle, Colors.red),
                _buildInputCard([
                  _buildTextField(_ukDebtController, 'UK Mortgage Balance', '£'),
                  _buildTextField(_euDebtController, 'EU Mortgage Balance', '€'),
                  _buildTextField(_creditCardController, 'Credit Card Balance', '£'),
                ]),
                
                _buildSectionHeader("Settings", Icons.settings, Colors.grey),
                _buildInputCard([
                  _buildTextField(_conversionRateController, 'EUR→GBP Conversion Rate', null),
                ]),

                const SizedBox(height: 20),
                // --- 4. NEW: BUTTON ROW ---
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save),
                        label: const Text("Save Inputs"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveToHistory,
                        icon: const Icon(Icons.history_edu),
                        label: const Text("Save History"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 80), 
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _loadAllData,
              tooltip: "Refresh Data",
              child: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
    );
  }
  
  // --- (All other helper widgets are unchanged) ---

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInputCard(List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String? prefix) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: prefix != null ? Padding(
            padding: const EdgeInsets.all(14.0),
            child: Text(prefix, style: const TextStyle(fontSize: 16)),
          ) : null,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
  
  Widget _buildSummaryCard(NumberFormat formatter) {
    return Card(
      elevation: 4,
      color: Colors.deepPurple.shade700,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              "TOTAL NET WORTH (GBP)", 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)
            ),
            const SizedBox(height: 8),
            Text(
              formatter.format(_netWorth),
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const Divider(color: Colors.white30, height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryColumn("Total Assets", formatter.format(_totalAssets), Colors.greenAccent.shade400),
                _buildSummaryColumn("Total Liabilities", formatter.format(_totalLiabilities), Colors.redAccent.shade400),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashflowCard(NumberFormat formatter) {
    final surplusColor = _monthlySurplus >= 0 ? Colors.green.shade600 : Colors.red.shade600;
    
    return Card(
      elevation: 4,
      color: Colors.blueGrey.shade800,
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              "MONTHLY CASH FLOW (GBP)", 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)
            ),
            const SizedBox(height: 8),
            Text(
              formatter.format(_monthlySurplus),
              style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: surplusColor),
            ),
            const Divider(color: Colors.white30, height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryColumn("Total Income", formatter.format(_totalMonthlyIncome), Colors.greenAccent.shade400),
                _buildSummaryColumn("Total Expenses", formatter.format(_totalMonthlyExpenses), Colors.redAccent.shade400),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSummaryColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPieChart(NumberFormat formatter) {
    final double total = _euAssetsGbp + _ukAssetsGbp + _euLiabilitiesGbp + _ukLiabilitiesGbp;
    final double euAssetPct = total > 0 ? (_euAssetsGbp / total) * 100 : 0;
    final double ukAssetPct = total > 0 ? (_ukAssetsGbp / total) * 100 : 0;
    final double euLiaPct = total > 0 ? (_euLiabilitiesGbp / total) * 100 : 0;
    final double ukLiaPct = total > 0 ? (_ukLiabilitiesGbp / total) * 100 : 0;
    
    final eurFormatter = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Breakdown (all converted to GBP)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 50,
                  sections: [
                    PieChartSectionData(
                      value: _euAssetsGbp,
                      title: "${euAssetPct.toStringAsFixed(0)}%",
                      color: Colors.green.shade600,
                      radius: 50,
                      titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    PieChartSectionData(
                      value: _ukAssetsGbp,
                      title: "${ukAssetPct.toStringAsFixed(0)}%",
                      color: Colors.green.shade300,
                      radius: 50,
                      titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    PieChartSectionData(
                      value: _euLiabilitiesGbp,
                      title: "${euLiaPct.toStringAsFixed(0)}%",
                      color: Colors.red.shade600,
                      radius: 50,
                      titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    PieChartSectionData(
                      value: _ukLiabilitiesGbp,
                      title: "${ukLiaPct.toStringAsFixed(0)}%",
                      color: Colors.red.shade300,
                      radius: 50,
                      titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildLegendItem(
              Colors.green.shade600, 
              "EU Assets", 
              formatter.format(_euAssetsGbp), 
              originalValue: eurFormatter.format(_euAssetsEur)
            ),
            _buildLegendItem(
              Colors.green.shade300, 
              "UK Assets", 
              formatter.format(_ukAssetsGbp)
            ),
            const Divider(height: 16),
            _buildLegendItem(
              Colors.red.shade600, 
              "EU Liabilities", 
              formatter.format(_euLiabilitiesGbp),
              originalValue: eurFormatter.format(_euLiabilitiesEur)
            ),
            _buildLegendItem(
              Colors.red.shade300, 
              "UK Liabilities", 
              formatter.format(_ukLiabilitiesGbp)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String title, String gbpValue, {String? originalValue}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(width: 16, height: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16)),
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
            gbpValue,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}