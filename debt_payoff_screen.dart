// lib/screens/debt_payoff_screen.dart

import 'package:flutter/material.dart';
import '../services/python_bridge.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:intl/intl.dart'; 

// --- Data Models (Copied from your other tabs) ---
// We can re-use the same models
class MortgageChartData {
  final int month;
  final double baselineBalance;
  final double overpayBalance;
  
  MortgageChartData(this.month, this.baselineBalance, this.overpayBalance);
  
  factory MortgageChartData.fromJson(Map<String, dynamic> json) {
    return MortgageChartData(
      (json['month'] as num? ?? 0).toInt(),
      (json['baseline_balance'] as num? ?? 0.0).toDouble(),
      (json['overpay_balance'] as num? ?? 0.0).toDouble(),
    );
  }
}

class YearlyScheduleRow {
  final int year;
  final double payment;
  final double principal;
  final double interest;
  final double balance;

  YearlyScheduleRow.fromJson(Map<String, dynamic> json)
      : year = (json['year'] as num? ?? 0).toInt(),
        payment = (json['payment'] as num? ?? 0.0).toDouble(),
        principal = (json['principal'] as num? ?? 0.0).toDouble(),
        interest = (json['interest'] as num? ?? 0.0).toDouble(),
        balance = (json['balance'] as num? ?? 0.0).toDouble();
}

class MonthlyScheduleRow {
  final int month;
  final double payment;
  final double principal;
  final double interest;
  final double balance;

  MonthlyScheduleRow.fromJson(Map<String, dynamic> json)
      : month = (json['month'] as num? ?? 0).toInt(),
        payment = (json['payment'] as num? ?? 0.0).toDouble(),
        principal = (json['principal'] as num? ?? 0.0).toDouble(),
        interest = (json['interest'] as num? ?? 0.0).toDouble(),
        balance = (json['balance'] as num? ?? 0.0).toDouble();
}


class DebtPayoffScreen extends StatefulWidget {
  const DebtPayoffScreen({super.key});
  @override
  State<DebtPayoffScreen> createState() => _DebtPayoffScreenState();
}

class _DebtPayoffScreenState extends State<DebtPayoffScreen> {
  final bridge = FlutterPythonBridge();
  String _result = "Enter details and click 'Run Simulation'."; 
  List<MortgageChartData> _chartData = []; 
  List<YearlyScheduleRow> _yearlySchedule = []; 
  List<MonthlyScheduleRow> _monthlySchedule = []; 
  
  bool _isMonthlyView = false; 
  Map<String, dynamic>? _summaryData; 

  // --- NEW Controllers for Credit Card ---
  final balanceController = TextEditingController();
  final aprController = TextEditingController();
  final minPctController = TextEditingController();
  final minFlatController = TextEditingController();
  final fixedPaymentController = TextEditingController();

  late final Map<String, TextEditingController> _controllers = {
    'balance': balanceController,
    'apr': aprController,
    'min_pct': minPctController,
    'min_flat': minFlatController,
    'fixed_payment': fixedPaymentController,
  };
  
  // --- Lifecycle & Persistence ---
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    for (var entry in _controllers.entries) {
      await prefs.setString('debt_payoff_${entry.key}', entry.value.text);
    }
    setState(() {
      _result = "✅ Settings saved successfully!";
    });
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final defaults = {
      'balance': '2000', 'apr': '21.9', 'min_pct': '2', 'min_flat': '25', 'fixed_payment': '100',
    };

    for (var entry in _controllers.entries) {
      final value = prefs.getString('debt_payoff_${entry.key}') ?? defaults[entry.key] ?? '';
      entry.value.text = value;
    }
    setState(() {
      _result = "Settings loaded. Click 'Run Simulation'.";
    });
  }

  @override
  void dispose() {
    _controllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  // --- Simulation Logic ---
  void _simulate() async {
    final inputData = {
      'balance': double.tryParse(balanceController.text) ?? 0.0,
      'apr': double.tryParse(aprController.text) ?? 0.0,
      'min_payment_pct': double.tryParse(minPctController.text) ?? 0.0,
      'min_payment_flat': double.tryParse(minFlatController.text) ?? 0.0,
      'fixed_payment': double.tryParse(fixedPaymentController.text) ?? 0.0,
    };
    
    print("DART IS SENDING (Debt Payoff): ${jsonEncode(inputData)}");

    setState(() {
      _result = "Running simulation...";
      _chartData = []; 
      _yearlySchedule = [];
      _monthlySchedule = []; 
      _summaryData = null; 
    });
    
    // Call our new Python function
    final resString = await bridge.run("credit card simulation", inputData); 
    
    try {
      final resData = jsonDecode(resString) as Map<String, dynamic>;

      if (resData.containsKey('error')) {
        setState(() {
          _result = "Python Error: ${resData['error']}";
          _summaryData = null;
        });
        return;
      }
      
      if (resData.containsKey('chart_data') && resData['chart_data'] is List) {
        _chartData = (resData['chart_data'] as List<dynamic>)
            .map((item) => MortgageChartData.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      
      if (resData.containsKey('yearly_schedule') && resData['yearly_schedule'] is List) {
        _yearlySchedule = (resData['yearly_schedule'] as List<dynamic>)
            .map((item) => YearlyScheduleRow.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      if (resData.containsKey('monthly_schedule') && resData['monthly_schedule'] is List) {
        _monthlySchedule = (resData['monthly_schedule'] as List<dynamic>)
            .map((item) => MonthlyScheduleRow.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      
      if (resData.containsKey('structured_summary') && resData['structured_summary'] is Map) {
        _summaryData = resData['structured_summary'] as Map<String, dynamic>;
        _result = "Simulation completed."; 
      } else {
        _result = resData['summary'] ?? "Error: Could not parse summary.";
      }

      setState(() {});

    } catch (e) {
      setState(() => _result = "API Error: Could not parse JSON response: $e\nRaw output:\n$resString");
    }
  }
  
  // --- Widget Builders ---
  static Widget defaultTitleWidget(double value, TitleMeta meta) {
    return const SizedBox();
  }
  
  Widget _buildTextField(TextEditingController controller, String label, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          border: const OutlineInputBorder(),
          isDense: true, 
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    if (_summaryData == null) {
      return Text(_result);
    }
    
    final formatter = NumberFormat.currency(locale: 'en_GB', symbol: '£');
    
    final minMonths = _summaryData!['min_pay_months'];
    final minInterest = _summaryData!['min_pay_interest'];
    final fixedMonths = _summaryData!['fixed_pay_months'];
    final fixedInterest = _summaryData!['fixed_pay_interest'];
    final interestSaved = _summaryData!['interest_saved'];
    final timeSaved = _summaryData!['time_saved_years'];

    Widget _buildSummaryRow(String label, String value, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.normal))),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.right),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Card 1: Minimum Payment
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Minimum Payment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                const Divider(),
                _buildSummaryRow(
                  "Time to Pay Off", 
                  minMonths == -1 ? "Debt Spiral!" : "${(minMonths / 12.0).toStringAsFixed(1)} years ($minMonths months)"
                ),
                _buildSummaryRow("Total Interest Paid", formatter.format(minInterest)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Card 2: Fixed Payment
        if(fixedMonths > 0)
        Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("With Fixed Payment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                const Divider(),
                _buildSummaryRow("Time to Pay Off", "${(fixedMonths / 12.0).toStringAsFixed(1)} years ($fixedMonths months)"),
                _buildSummaryRow("Total Interest Paid", formatter.format(fixedInterest)),
                const Divider(height: 15),
                _buildSummaryRow("Time Saved", "${timeSaved.toStringAsFixed(1)} years", color: Colors.green.shade700),
                _buildSummaryRow("Interest Saved", formatter.format(interestSaved), color: Colors.green.shade700),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildChart() {
    if (_chartData.isEmpty) {
      return const Center(child: Text("Run simulation to view chart data."));
    }
    
    double maxY = _chartData.map((e) => e.baselineBalance).reduce((a, b) => a > b ? a : b);
    double maxX = _chartData.map((e) => e.month.toDouble()).reduce((a, b) => a > b ? a : b);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          height: 300, 
          child: LineChart(
            LineChartData(
              minY: 0, maxY: maxY * 1.05, minX: 0, maxX: maxX,
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(reservedSize: 0, getTitlesWidget: defaultTitleWidget),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(reservedSize: 0, getTitlesWidget: defaultTitleWidget),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: const Text('Months'),
                  sideTitles: SideTitles(
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      axisSide: meta.axisSide, space: 8.0,
                      child: Text(value.toInt().toString()),
                    ),
                    reservedSize: 30, interval: 60, 
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: const Text('Balance (£)'),
                  sideTitles: SideTitles(
                    getTitlesWidget: (value, meta) => Text('£${(value / 1000).toInt()}k'),
                    reservedSize: 40, interval: maxY / 4, 
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true, drawVerticalLine: true,
                horizontalInterval: maxY / 4, verticalInterval: 60,
              ),
              borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey)),
              
              lineBarsData: [
                LineChartBarData(
                  spots: _chartData.map((data) => FlSpot(data.month.toDouble(), data.baselineBalance)).toList(),
                  isCurved: true, color: Colors.red.shade800, barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: _chartData.map((data) => FlSpot(data.month.toDouble(), data.overpayBalance)).toList(),
                  isCurved: true, color: Colors.green.shade800, barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleTable() {
    if (_yearlySchedule.isEmpty) {
      return const Center(child: Text("Run simulation to view the amortization schedule."));
    }
    
    final List<Object> data = _isMonthlyView ? _monthlySchedule : _yearlySchedule;
    final currencySymbol = '£';
    
    List<DataColumn> columns;
    if (_isMonthlyView) {
      columns = [
        const DataColumn(label: Text('Month', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Payment ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
        DataColumn(label: Text('Principal ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
        DataColumn(label: Text('Interest ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
        DataColumn(label: Text('Balance ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
      ];
    } else {
       columns = [
        const DataColumn(label: Text('Year', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Payment ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
        DataColumn(label: Text('Principal ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
        DataColumn(label: Text('Interest ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
        DataColumn(label: Text('Balance ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
      ];
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Fixed Payment Schedule", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                
                Row(
                  children: [
                    Text(_isMonthlyView ? 'Monthly' : 'Yearly'),
                    Switch(
                      value: _isMonthlyView,
                      onChanged: (value) => setState(() => _isMonthlyView = value),
                      activeThumbColor: Colors.blue,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 40,
                headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
                columns: columns,
                rows: data.map((item) {
                  dynamic row = _isMonthlyView ? item as MonthlyScheduleRow : item as YearlyScheduleRow;
                  
                  return DataRow(
                    cells: [
                      DataCell(Text(_isMonthlyView 
                          ? row.month.toString() 
                          : row.year == 0 ? '0 (Start)' : row.year.toString())), 
                          
                      DataCell(Text(row.payment.toStringAsFixed(2))),
                      DataCell(Text(row.principal.toStringAsFixed(2))),
                      DataCell(Text(row.interest.toStringAsFixed(2))),
                      DataCell(Text(row.balance.toStringAsFixed(2), style: TextStyle(fontWeight: row.balance <= 0.01 ? FontWeight.bold : FontWeight.normal))),
                    ]
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Credit Card Payoff", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Debt Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blue)),
                    const SizedBox(height: 10),
                    _buildTextField(balanceController, 'Current Balance (£)', icon: Icons.currency_pound),
                    _buildTextField(aprController, 'Annual Interest Rate (APR) %', icon: Icons.percent),
                    
                    const SizedBox(height: 10),
                    const Text("Minimum Payment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.red)),
                    _buildTextField(minPctController, 'Min. Payment (% of balance)', icon: Icons.pie_chart),
                    _buildTextField(minFlatController, 'Min. Payment (flat amount £)', icon: Icons.money),

                    const SizedBox(height: 10),
                    const Text("Your Plan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.green)),
                    _buildTextField(fixedPaymentController, 'Your Fixed Monthly Payment (£)', icon: Icons.payments),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // --- Buttons ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _simulate,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Run Simulation"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text("Save Settings"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade400,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // --- Results ---
            _buildSummaryCard(),
            const SizedBox(height: 20),
            const Text("Debt Balance Over Time", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            _buildChart(),
            const SizedBox(height: 20),
            _buildScheduleTable(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}