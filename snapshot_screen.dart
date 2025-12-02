// lib/screens/snapshot_screen.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart'; 
import '../services/savings_service.dart';
import '../services/budget_service.dart';
import '../services/history_service.dart';
import '../services/backup_service.dart'; 
import '../services/currency_service.dart'; // Ensure this is imported

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
  bool _isUpdatingRates = false; 

  double _euAssetsGbp = 0.0;
  double _ukAssetsGbp = 0.0;
  double _euLiabilitiesGbp = 0.0;
  double _ukLiabilitiesGbp = 0.0;

  double _euAssetsEur = 0.0;
  double _euLiabilitiesEur = 0.0;
  
  // Savings State (Pure Savings)
  double _totalSavingsGbp = 0.0;
  double _ukSavingsGbp = 0.0;
  double _euSavingsEur = 0.0;

  double _totalMonthlyIncome = 0.0;
  double _totalMonthlyExpenses = 0.0;
  double _monthlySurplus = 0.0;
  
  List<FinancialSnapshot> _history = []; 

  List<SavingsPlatform> _loadedPlatforms = [];
  List<BudgetItem> _loadedBudgetItems = [];

  // --- Controllers ---
  final _euPropertyController = TextEditingController();
  final _ukPropertyController = TextEditingController();
  final _euDebtController = TextEditingController();
  final _ukDebtController = TextEditingController();
  final _creditCardController = TextEditingController();
  final _conversionRateController = TextEditingController(text: "0.85");
  final _inverseRateController = TextEditingController(text: "1.17");

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
  final _historyService = HistoryService();
  final _backupService = BackupService();
  final _currencyService = CurrencyService();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _removeListeners();
    _euPropertyController.dispose();
    _ukPropertyController.dispose();
    _euDebtController.dispose();
    _ukDebtController.dispose();
    _creditCardController.dispose();
    _conversionRateController.dispose();
    _inverseRateController.dispose();
    super.dispose();
  }

  void _addListeners() {
    _euPropertyController.addListener(_calculateSnapshot);
    _ukPropertyController.addListener(_calculateSnapshot);
    _euDebtController.addListener(_calculateSnapshot);
    _ukDebtController.addListener(_calculateSnapshot);
    _creditCardController.addListener(_calculateSnapshot);
  }

  void _removeListeners() {
    _euPropertyController.removeListener(_calculateSnapshot);
    _ukPropertyController.removeListener(_calculateSnapshot);
    _euDebtController.removeListener(_calculateSnapshot);
    _ukDebtController.removeListener(_calculateSnapshot);
    _creditCardController.removeListener(_calculateSnapshot);
  }

  // --- Rate Handlers ---
  void _onEurGbpChanged(String val) {
    if (val.isEmpty) return;
    final rate = double.tryParse(val);
    if (rate != null && rate > 0) {
      final inverse = 1 / rate;
      if ((double.tryParse(_inverseRateController.text) ?? 0) != inverse) {
         _inverseRateController.text = inverse.toStringAsFixed(4);
      }
      _calculateSnapshot();
    }
  }

  void _onGbpEurChanged(String val) {
    if (val.isEmpty) return;
    final rate = double.tryParse(val);
    if (rate != null && rate > 0) {
      final inverse = 1 / rate;
      if ((double.tryParse(_conversionRateController.text) ?? 0) != inverse) {
         _conversionRateController.text = inverse.toStringAsFixed(4);
      }
      _calculateSnapshot();
    }
  }

  Future<void> _fetchLiveRates() async {
    setState(() => _isUpdatingRates = true);
    
    final rate = await _currencyService.fetchEurToGbpRate();
    
    if (rate != null) {
      if (mounted) {
        _conversionRateController.text = rate.toString();
        _onEurGbpChanged(rate.toString());
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated: 1 EUR = £$rate'), backgroundColor: Colors.green),
        );
        _saveSettings(); 
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch rates. Check internet.'), backgroundColor: Colors.red),
        );
      }
    }
    
    if (mounted) setState(() => _isUpdatingRates = false);
  }

  Future<void> _loadAllData() async {
    if (!_isLoading) setState(() => _isLoading = true);
    
    _removeListeners();
    final prefs = await SharedPreferences.getInstance();

    final results = await Future.wait([
      _savingsService.loadPlatforms(),
      _budgetService.loadItems(),
      _historyService.loadHistory(), 
    ]);
    
    _loadedPlatforms = results[0] as List<SavingsPlatform>;
    _loadedBudgetItems = results[1] as List<BudgetItem>;
    
    _history = results[2] as List<FinancialSnapshot>; 
    _history.sort((a, b) => a.savedDate.compareTo(b.savedDate)); 

    // Sort history chronologically for the Time Machine chart (Oldest -> Newest)
    _history.sort((a, b) => a.savedDate.compareTo(b.savedDate));

    _conversionRateController.text = prefs.getString('snapshot_conversion_rate') ?? '0.85';
    _onEurGbpChanged(_conversionRateController.text);

    _euPropertyController.text = prefs.getString('eu_mortgage_value') ?? '0';
    _ukPropertyController.text = prefs.getString('uk_mortgage_value') ?? '0';
    _euDebtController.text = prefs.getString('eu_mortgage_loan') ?? '0';
    _ukDebtController.text = prefs.getString('uk_mortgage_loan') ?? '0';
    _creditCardController.text = prefs.getString('debt_payoff_balance') ?? '0';

    _calculateSnapshot();
    _addListeners();
    if (mounted) setState(() => _isLoading = false);
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
  
  Future<void> _generateAISummary() async {
    final formatter = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);
    final summary = """
Here is a structured summary of your financial snapshot:

**Net Worth:** ${formatter.format(_netWorth)}

**Assets Total:** ${formatter.format(_totalAssets)}
- UK Assets: ${formatter.format(_ukAssetsGbp)}
- EU Assets: ${formatter.format(_euAssetsGbp)} (≈ ${NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0).format(_euAssetsEur)})

**Liabilities Total:** ${formatter.format(_totalLiabilities)}
- UK Liabilities: ${formatter.format(_ukLiabilitiesGbp)}
- EU Liabilities: ${formatter.format(_euLiabilitiesGbp)} (≈ ${NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0).format(_euLiabilitiesEur)})

**Cashflow Overview:**
- Monthly Income: ${formatter.format(_totalMonthlyIncome)}
- Monthly Expenses: ${formatter.format(_totalMonthlyExpenses)}
- Monthly Surplus: ${formatter.format(_monthlySurplus)}

**Exchange Rate:**
- 1 EUR = £${_conversionRateController.text}
""";

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("AI Financial Summary"),
        content: SingleChildScrollView(child: Text(summary)),
        actions: [
          TextButton(child: const Text("Close"), onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  Future<void> _saveToHistory() async {
    final bool? didConfirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save Monthly History"),
        content: Text("Save a snapshot for ${DateFormat('MMMM yyyy').format(DateTime.now())}? This will overwrite any existing snapshot for this month."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Save")),
        ],
      ),
    );

    if (didConfirm != true) return;
    setState(() => _isLoading = true);

    try {
      double euSavings = 0.0;
      double gbpSavings = 0.0;
      for (var p in _loadedPlatforms) {
        if (p.currency == "EUR") euSavings += p.balance;
        else gbpSavings += p.balance;
      }

      final double euDebt = double.tryParse(_euDebtController.text) ?? 0.0;
      final double ukDebt = double.tryParse(_ukDebtController.text) ?? 0.0;
      final double ccDebt = double.tryParse(_creditCardController.text) ?? 0.0;

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
        monthlySurplus: _monthlySurplus,
        budgetItems: _loadedBudgetItems.map((e) => e.toJson()).toList(),
        savingsPlatforms: _loadedPlatforms.map((e) => e.toJson()).toList(),
      );

      await _historyService.saveSnapshot(snapshot);
      _history = await _historyService.loadHistory();
      _history.sort((a, b) => a.savedDate.compareTo(b.savedDate)); 

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📈 History snapshot saved!'), backgroundColor: Colors.deepPurple));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save history: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateSnapshot() {
    double euSavings = 0.0;
    double gbpSavings = 0.0;
    for (var p in _loadedPlatforms) {
      if (p.currency == "EUR") euSavings += p.balance;
      else gbpSavings += p.balance;
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
    
    final double totalSavingsGbp = gbpSavings + (euSavings * rate);

    double tempMonthlyIncome = 0.0;
    double tempMonthlyExpenses = 0.0;
    
    for (var item in _loadedBudgetItems) {
      double amount = item.amount;
      if (item.currency == "EUR") amount = amount * rate;

      switch (item.frequency) {
        case BudgetFrequency.Weekly: amount *= 4.3333; break;
        case BudgetFrequency.Quarterly: amount /= 3.0; break;
        case BudgetFrequency.Yearly: amount /= 12.0; break;
        case BudgetFrequency.Monthly: break;
      }

      if (item.type == BudgetItemType.Income) tempMonthlyIncome += amount;
      else tempMonthlyExpenses += amount;
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
      
      _totalSavingsGbp = totalSavingsGbp;
      _ukSavingsGbp = gbpSavings;
      _euSavingsEur = euSavings;

      _totalMonthlyIncome = tempMonthlyIncome;
      _totalMonthlyExpenses = tempMonthlyExpenses;
      _monthlySurplus = tempMonthlyIncome - tempMonthlyExpenses;
    });
  }

  Future<void> _exportBackup() async {
    setState(() => _isLoading = true);
    try {
      final path = await _backupService.exportData();
      if (!mounted) return;
      await Share.shareXFiles([XFile(path)], text: 'Financial Assistant Backup');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup file created and shared!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup Failed: ${e.toString()}'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);
        await _backupService.importData(result.files.single.path!);
        await _loadAllData();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Data restored successfully! App state reloaded.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import Failed: ${e.toString()}'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UPDATED: Time Machine Chart (Interactive & Gradient) ---
  Widget _buildNetWorthChart(NumberFormat formatter) {
    if (_history.length < 2) {
      return Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(Icons.show_chart, size: 40, color: Colors.grey),
              const SizedBox(height: 8),
              Text("Time Machine", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text("Save at least 2 monthly snapshots to activate the time travel graph.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    
    // Sort history by date to ensure the line goes forward in time
    final sortedHistory = List<FinancialSnapshot>.from(_history);
    sortedHistory.sort((a, b) => a.savedDate.compareTo(b.savedDate));

    final List<FlSpot> spots = [];
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (int i = 0; i < sortedHistory.length; i++) {
      final snapshot = sortedHistory[i];
      final spot = FlSpot(i.toDouble(), snapshot.netWorth);
      spots.add(spot);
      if (snapshot.netWorth < minY) minY = snapshot.netWorth;
      if (snapshot.netWorth > maxY) maxY = snapshot.netWorth;
    }
    
    // Add current live value as the final "Now" point
    final currentPointIndex = sortedHistory.length.toDouble();
    spots.add(FlSpot(currentPointIndex, _netWorth));
    if (_netWorth < minY) minY = _netWorth;
    if (_netWorth > maxY) maxY = _netWorth;
    
    final yBuffer = (maxY - minY).abs() * 0.1;
    minY = (minY - yBuffer).clamp(0.0, double.infinity); // No negative scale unless debt > assets
    maxY += yBuffer;

    // Define Gradient Colors
    final List<Color> gradientColors = [
      Colors.cyanAccent,
      Colors.blueAccent,
    ];

    return Card(
      elevation: 4,
      shadowColor: Colors.blueAccent.withOpacity(0.3),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Time Machine (Net Worth)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Icon(Icons.history, color: Colors.blueAccent.shade100),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: currentPointIndex,
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxY - minY) / 4,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          // Show "Now" for current
                          if (index == currentPointIndex) {
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: const Text('Now', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                            );
                          }
                          // Show every other month for history
                          if (index < sortedHistory.length && index % 2 == 0) {
                            final date = sortedHistory[index].savedDate;
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(DateFormat('MMM').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                        interval: (maxY - minY) / 4,
                        getTitlesWidget: (value, meta) {
                          if (value >= 1000000) return Text('£${(value/1000000).toStringAsFixed(1)}M', style: const TextStyle(fontSize: 10, color: Colors.grey));
                          if (value >= 1000) return Text('£${(value/1000).toInt()}k', style: const TextStyle(fontSize: 10, color: Colors.grey));
                          return Text('£${value.toInt()}', style: const TextStyle(fontSize: 10, color: Colors.grey));
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          int index = spot.x.toInt();
                          String dateLabel = "Now";
                          if (index < sortedHistory.length) {
                            dateLabel = DateFormat('MMM yyyy').format(sortedHistory[index].savedDate);
                          }
                          return LineTooltipItem(
                            '$dateLabel\n',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            children: [
                              TextSpan(
                                text: formatter.format(spot.y),
                                style: TextStyle(color: Colors.cyanAccent.shade100, fontWeight: FontWeight.w500),
                              ),
                            ],
                          );
                        }).toList();
                      },
                    ),
                    handleBuiltInTouches: true,
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      gradient: LinearGradient(colors: gradientColors),
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.white,
                            strokeWidth: 2,
                            strokeColor: Colors.blueAccent,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: gradientColors.map((color) => color.withOpacity(0.2)).toList(),
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Other Widgets (Assets, Cashflow, Pie, etc) are unchanged ---
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
                  
                  // The New Time Machine
                  _buildNetWorthChart(formatter),
                  
                  _buildCashflowCard(formatter),
                  _buildAssetsCard(formatter),
                  _buildPieChart(formatter),
                ],

                _buildSectionHeader("Assets (What you Own)", Icons.add_circle, Colors.green),
                _buildInputCard([
                  _buildTextField(_ukPropertyController, 'UK Property Value', '£'),
                  _buildTextField(_euPropertyController, 'EU Property Value', '€'),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text("Savings & Investments are managed via the 💰 icon in the app bar. Press Refresh to update.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]),

                _buildSectionHeader("Liabilities (What you Owe)", Icons.remove_circle, Colors.red),
                _buildInputCard([
                  _buildTextField(_ukDebtController, 'UK Mortgage Balance', '£'),
                  _buildTextField(_euDebtController, 'EU Mortgage Balance', '€'),
                  _buildTextField(_creditCardController, 'Credit Card Balance', '£'),
                ]),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionHeader("Settings & Rates", Icons.settings, Colors.grey),
                    if (!_isLoading)
                      IconButton(
                        icon: _isUpdatingRates 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                            : const Icon(Icons.refresh, color: Colors.blue),
                        onPressed: _fetchLiveRates,
                        tooltip: "Refresh Live Rates",
                      )
                  ],
                ),
                _buildInputCard([
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _conversionRateController,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          onChanged: _onEurGbpChanged,
                          decoration: const InputDecoration(labelText: "EUR → GBP", border: OutlineInputBorder(), isDense: true, suffixText: "£"),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _inverseRateController,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          onChanged: _onGbpEurChanged,
                          decoration: const InputDecoration(labelText: "GBP → EUR", border: OutlineInputBorder(), isDense: true, suffixText: "€"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text("Tap refresh icon above to fetch live market rates.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),

                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(child: ElevatedButton.icon(onPressed: _saveSettings, icon: const Icon(Icons.save), label: const Text("Save Inputs"), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade400, foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(vertical: 12)))),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(onPressed: _saveToHistory, icon: const Icon(Icons.history_edu), label: const Text("Save History"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)))),
                  ],
                ),

                const SizedBox(height: 12),
                ElevatedButton.icon(onPressed: _generateAISummary, icon: const Icon(Icons.auto_awesome), label: const Text("AI Financial Summary"), style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14))),
                
                const SizedBox(height: 20),
                _buildSectionHeader("Data Management", Icons.cloud_upload, Colors.orange),
                Row(
                  children: [
                    Expanded(child: ElevatedButton.icon(onPressed: _isLoading ? null : _exportBackup, icon: const Icon(Icons.cloud_upload), label: const Text("Export Full Backup"), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white))),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(onPressed: _isLoading ? null : _importBackup, icon: const Icon(Icons.cloud_download), label: const Text("Import Data"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white))),
                  ],
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
          Positioned(bottom: 16, right: 16, child: FloatingActionButton(onPressed: _loadAllData, tooltip: "Refresh Data", child: const Icon(Icons.refresh))),
        ],
      ),
    );
  }

  // --- Helper Widgets Below (Unchanged from your previous file) ---
  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(padding: const EdgeInsets.only(top: 24.0, bottom: 8.0), child: Row(children: [Icon(icon, color: color, size: 28), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]));
  }

  Widget _buildInputCard(List<Widget> children) {
    return Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(16.0), child: Column(children: children)));
  }

  Widget _buildTextField(TextEditingController controller, String label, String? prefix) {
    return Padding(padding: const EdgeInsets.only(bottom: 12.0), child: TextFormField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label, prefixIcon: prefix != null ? Padding(padding: const EdgeInsets.all(14.0), child: Text(prefix, style: const TextStyle(fontSize: 16))) : null, border: const OutlineInputBorder(), isDense: true)));
  }

  Widget _buildAssetsCard(NumberFormat formatter) {
    final eurFormatter = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
    final rate = double.tryParse(_conversionRateController.text) ?? 0.85;
    final euSavingsConverted = _euSavingsEur * rate;

    return Card(elevation: 4, margin: const EdgeInsets.only(top: 16), color: Colors.deepPurple.shade700, child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Text("TOTAL SAVINGS & ASSETS (GBP)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 8),
            Text(formatter.format(_totalSavingsGbp), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)),
            const Divider(color: Colors.white30, height: 24),
            _buildLegendItem(Colors.green.shade300, "UK Assets (GBP)", formatter.format(_ukSavingsGbp)),
            _buildLegendItem(Colors.blue.shade300, "EU Assets (EUR)", formatter.format(euSavingsConverted), originalValue: eurFormatter.format(_euSavingsEur)),
          ])));
  }

  Widget _buildCashflowCard(NumberFormat formatter) {
    final surplusColor = _monthlySurplus >= 0 ? Colors.green.shade600 : Colors.red.shade600;
    return Card(elevation: 4, color: Colors.blueGrey.shade800, margin: const EdgeInsets.only(top: 16), child: Padding(padding: const EdgeInsets.all(20.0), child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Text("MONTHLY CASH FLOW (GBP)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 8),
            Text(formatter.format(_monthlySurplus), style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: surplusColor)),
            const Divider(color: Colors.white30, height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _buildSummaryColumn("Total Income", formatter.format(_totalMonthlyIncome), Colors.greenAccent),
                _buildSummaryColumn("Total Expenses", formatter.format(_totalMonthlyExpenses), Colors.redAccent),
              ]),
          ])));
  }

  Widget _buildSummaryCard(NumberFormat formatter) {
    return Card(elevation: 4, color: Colors.deepPurple.shade700, child: Padding(padding: const EdgeInsets.all(20.0), child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Text("TOTAL NET WORTH (GBP)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 8),
            Text(formatter.format(_netWorth), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)),
            const Divider(color: Colors.white30, height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _buildSummaryColumn("Total Assets", formatter.format(_totalAssets), Colors.greenAccent.shade400),
                _buildSummaryColumn("Total Liabilities", formatter.format(_totalLiabilities), Colors.redAccent.shade400),
              ]),
          ])));
  }

  Widget _buildSummaryColumn(String label, String value, Color color) {
    return Column(children: [Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)), const SizedBox(height: 4), Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold))]);
  }

  Widget _buildPieChart(NumberFormat formatter) {
    final double total = _euAssetsGbp + _ukAssetsGbp + _euLiabilitiesGbp + _ukLiabilitiesGbp;
    final double euAssetPct = total > 0 ? (_euAssetsGbp / total) * 100 : 0;
    final double ukAssetPct = total > 0 ? (_ukAssetsGbp / total) * 100 : 0;
    final double euLiaPct = total > 0 ? (_euLiabilitiesGbp / total) * 100 : 0;
    final double ukLiaPct = total > 0 ? (_ukLiabilitiesGbp / total) * 100 : 0;
    final eurFormatter = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

    return Card(elevation: 2, margin: const EdgeInsets.only(top: 16), child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Breakdown (all converted to GBP)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(height: 200, child: PieChart(PieChartData(sectionsSpace: 4, centerSpaceRadius: 50, sections: [
                    PieChartSectionData(value: _euAssetsGbp, title: "${euAssetPct.toStringAsFixed(0)}%", color: Colors.green.shade600, radius: 50, titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    PieChartSectionData(value: _ukAssetsGbp, title: "${ukAssetPct.toStringAsFixed(0)}%", color: Colors.green.shade300, radius: 50, titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    PieChartSectionData(value: _euLiabilitiesGbp, title: "${euLiaPct.toStringAsFixed(0)}%", color: Colors.red.shade600, radius: 50, titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    PieChartSectionData(value: _ukLiabilitiesGbp, title: "${ukLiaPct.toStringAsFixed(0)}%", color: Colors.red.shade300, radius: 50, titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  ]))),
            const SizedBox(height: 24),
            _buildLegendItem(Colors.green.shade600, "EU Assets", formatter.format(_euAssetsGbp), originalValue: eurFormatter.format(_euAssetsEur)),
            _buildLegendItem(Colors.green.shade300, "UK Assets", formatter.format(_ukAssetsGbp)),
            const Divider(height: 16),
            _buildLegendItem(Colors.red.shade600, "EU Liabilities", formatter.format(_euLiabilitiesGbp), originalValue: eurFormatter.format(_euLiabilitiesEur)),
            _buildLegendItem(Colors.red.shade300, "UK Liabilities", formatter.format(_ukLiabilitiesGbp)),
          ])));
  }

  Widget _buildLegendItem(Color color, String title, String gbpValue, {String? originalValue}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row(children: [
          Container(width: 16, height: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          if (originalValue != null) Padding(padding: const EdgeInsets.only(right: 8.0), child: Text("($originalValue)", style: const TextStyle(fontSize: 15, color: Colors.grey))),
          Text(gbpValue, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]));
  }
}