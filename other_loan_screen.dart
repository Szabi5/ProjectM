// lib/screens/other_loan_screen.dart

import 'package:flutter/material.dart';
import '../services/python_bridge.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:intl/intl.dart'; 

// --- Data Models (Copied from your other tabs) ---

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


class OtherLoanScreen extends StatefulWidget {
  const OtherLoanScreen({super.key});
  @override
  State<OtherLoanScreen> createState() => _OtherLoanScreenState();
}

class _OtherLoanScreenState extends State<OtherLoanScreen> {
  final bridge = FlutterPythonBridge();
  String _result = "Enter details and click 'Run Projection'."; 
  List<MortgageChartData> _chartData = []; 
  List<YearlyScheduleRow> _yearlySchedule = []; 
  List<MonthlyScheduleRow> _monthlySchedule = []; 
  
  bool _isMonthlyView = false; 
  Map<String, dynamic>? _summaryData; 

  // --- Simplified Controllers ---
  final loanController = TextEditingController();
  final rateController = TextEditingController();
  final yearsController = TextEditingController();
  final overpayController = TextEditingController(); 

  late final Map<String, TextEditingController> _controllers = {
    'loan': loanController, 
    'rate': rateController, 
    'years': yearsController,
    'overpay': overpayController,
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
      // Use a unique prefix for this tab's saved data
      await prefs.setString('other_loan_${entry.key}', entry.value.text);
    }
    setState(() {
      _result = "✅ Settings saved successfully!";
    });
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final defaults = {
      'loan': '10000', 'rate': '7.9', 'years': '5', 'overpay': '50', 
    };

    for (var entry in _controllers.entries) {
      final value = prefs.getString('other_loan_${entry.key}') ?? defaults[entry.key] ?? '';
      entry.value.text = value;
    }
    setState(() {
      _result = "Settings loaded. Click 'Run Projection'.";
    });
  }

  @override
  void dispose() {
    _controllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  // --- Simulation Logic ---
  void _simulate() async {
    // We send the *full payload* that the Python engine expects,
    // just with the unused ones set to 0 or ""
    final inputData = {
      'loan': double.tryParse(loanController.text) ?? 0.0,
      'rate': double.tryParse(rateController.text) ?? 0.0,
      'years': int.tryParse(yearsController.text) ?? 0,
      'monthly_overpay': double.tryParse(overpayController.text) ?? 0.0,
      
      // --- Send 0/" for all other fields ---
      'value': 0.0,
      'overpay_pct_of_base': 0.0,
      'annual_lump': 0.0,
      'annual_lump_month': 12,
      'one_off_lump': 0.0,
      'one_off_lump_month': 0,
      'inflation': 0.0,
      'rate_changes': "",
    };
    
    print("DART IS SENDING (Other Loan): ${jsonEncode(inputData)}");

    setState(() {
      _result = "Running simulation...";
      _chartData = []; 
      _yearlySchedule = [];
      _monthlySchedule = []; 
      _summaryData = null; 
    });
    
    // We can re-use "mortgage simulation" because it's the same math!
    final resString = await bridge.run("mortgage simulation", inputData); 
    
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
  
  // Using the same styled text field from your other tabs
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
    
    final basePayment = _summaryData!['base_monthly_payment'];
    final overpayPayment = _summaryData!['overpay_monthly_payment'];
    final timeSaved = _summaryData!['time_saved_years'];
    final interestSaved = _summaryData!['interest_saved'];
    // LTV is removed, as 'value' is 0

    Widget _buildSummaryRow(String label, String value, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.normal)),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );
    }
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Loan Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(),
            
            _buildSummaryRow("Base Monthly Payment", formatter.format(basePayment)),
            _buildSummaryRow("Total Monthly Payment", formatter.format(overpayPayment), color: Colors.green),
            
            const Divider(height: 15),
            
            _buildSummaryRow("Time Saved", "${timeSaved.toStringAsFixed(1)} years", color: Colors.red),
            _buildSummaryRow("Interest Saved", formatter.format(interestSaved), color: Colors.red),
          ],
        ),
      ),
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
                  isCurved: true, color: Colors.blue.shade800, barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: _chartData.map((data) => FlSpot(data.month.toDouble(), data.overpayBalance)).toList(),
                  isCurved: true, color: Colors.red.shade800, barWidth: 2,
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
                const Text("Amortization Schedule", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                
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
            const Text("Other Loan Calculator", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            
            // --- Simplified Input Card ---
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Loan Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blue)),
                    const SizedBox(height: 10),
                    _buildTextField(loanController, 'Loan Amount (£)', icon: Icons.currency_pound),
                    _buildTextField(rateController, 'Annual Interest Rate (%)', icon: Icons.percent),
                    _buildTextField(yearsController, 'Remaining Years', icon: Icons.calendar_month),
                    _buildTextField(overpayController, 'Monthly Overpayment (£)', icon: Icons.payments),
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
                    label: const Text("Run Projection"),
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
            const Text("Amortization Balance Over Time", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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