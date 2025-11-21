// lib/screens/overpayment.dart

import 'package:flutter/material.dart';
import '../services/python_bridge.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:intl/intl.dart'; 

// --- Data Models (NULL-SAFE) ---

class OverpaymentChartData { 
  final int month;
  final double balance;
  
  OverpaymentChartData(this.month, this.balance);
  
  factory OverpaymentChartData.fromJson(Map<String, dynamic> json) {
    return OverpaymentChartData(
      (json['month'] as num? ?? 0).toInt(),
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


class OverpaymentScreen extends StatefulWidget { 
  const OverpaymentScreen({super.key});
  @override
  State<OverpaymentScreen> createState() => _OverpaymentScreenState();
}

class _OverpaymentScreenState extends State<OverpaymentScreen> { 
  final bridge = FlutterPythonBridge();
  String _result = "Enter details and click 'Calculate'."; 
  List<OverpaymentChartData> _chartData = []; 
  List<YearlyScheduleRow> _yearlySchedule = []; 
  List<MonthlyScheduleRow> _monthlySchedule = []; 
  
  bool _isMonthlyView = false; 
  Map<String, dynamic>? _summaryData; 

  // --- Controllers ---
  final loanController = TextEditingController();
  final rateController = TextEditingController();
  final currentYearsController = TextEditingController(); 
  final targetTimeController = TextEditingController(); 
  final requiredPaymentController = TextEditingController(); // This is for output only

  late final Map<String, TextEditingController> _controllers = {
    'loan': loanController, 
    'rate': rateController, 
    'currentYears': currentYearsController, 
    'targetTime': targetTimeController,
  };
  
  // --- Persistence ---
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    for (var entry in _controllers.entries) {
      await prefs.setString('overpayment_${entry.key}', entry.value.text); 
    }
    setState(() => _result = "✅ Settings saved successfully!");
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = {
      'loan': '100000', 'rate': '5.0', 'currentYears': '25', 'targetTime': '15', 
    };
    for (var entry in _controllers.entries) {
      final value = prefs.getString('overpayment_${entry.key}') ?? defaults[entry.key] ?? '';
      entry.value.text = value;
    }
    setState(() => _result = "Settings loaded. Click 'Calculate'.");
  }

  @override
  void dispose() {
    _controllers.values.forEach((c) => c.dispose());
    requiredPaymentController.dispose();
    super.dispose();
  }

  // --- Simulation Logic (with CORRECTED JSON keys) ---

  void _simulate() async {
    final inputData = {
      'loan_amount': double.tryParse(loanController.text) ?? 0.0,
      'annual_rate': double.tryParse(rateController.text) ?? 0.0,
      'current_years': int.tryParse(currentYearsController.text) ?? 0, 
      'target_years': int.tryParse(targetTimeController.text) ?? 0,
    };
    
    // --- DEBUGGING LINE ---
    print("DART IS SENDING (Overpayment): ${jsonEncode(inputData)}");

    setState(() {
      _result = "Running calculation..."; _chartData = []; _yearlySchedule = [];
      _monthlySchedule = []; _summaryData = null; 
      requiredPaymentController.text = '';
    });
    
    //
    // --- THIS IS THE FIX ---
    // Pass the 'inputData' map directly, not the encoded string
    //
    final resString = await bridge.run("Overpayment simulation logic", inputData); 
    
    try {
      final resData = jsonDecode(resString) as Map<String, dynamic>;

      if (resData.containsKey('error')) {
        setState(() {
          _result = "Python Error: ${resData['error']}";
          _summaryData = null;
        });
        return;
      }
      
      _chartData = (resData['chart_data'] as List<dynamic>?)?.map((item) => OverpaymentChartData.fromJson(item as Map<String, dynamic>)).toList() ?? [];
      _yearlySchedule = (resData['yearly_schedule'] as List<dynamic>?)?.map((item) => YearlyScheduleRow.fromJson(item as Map<String, dynamic>)).toList() ?? [];
      _monthlySchedule = (resData['monthly_schedule'] as List<dynamic>?)?.map((item) => MonthlyScheduleRow.fromJson(item as Map<String, dynamic>)).toList() ?? [];
      
      if (resData.containsKey('structured_summary') && resData['structured_summary'] is Map) {
        _summaryData = resData['structured_summary'] as Map<String, dynamic>;
        
        final requiredPayment = _summaryData!['target_monthly'] ?? 0.0;
        requiredPaymentController.text = requiredPayment.toStringAsFixed(2);
        
        _result = "Calculation completed."; 
      } else {
        _result = resData['summary'] ?? "Error: Could not parse structured summary.";
      }

      setState(() {});

    } catch (e) {
      setState(() => _result = "API Error: Could not parse JSON response: $e\nRaw output:\n$resString");
    }
  }
  
  // --- (All Widget Builders are unchanged) ---

  Widget _buildTextField(TextEditingController controller, String label, {IconData? icon, bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        readOnly: readOnly,
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
    if (_summaryData == null) return Text(_result);
    
    final formatter = NumberFormat.currency(locale: 'en_GB', symbol: '£'); 
    
    final basePayment = _summaryData!['base_monthly'];
    final targetPayment = _summaryData!['target_monthly'];
    final reqOverpay = _summaryData!['required_overpayment'];
    final capStatus = _summaryData!['cap_status'];

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
            const Text("Required Overpayment Results", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(),
            _buildSummaryRow("Base Monthly Payment", formatter.format(basePayment)),
            _buildSummaryRow("Payment for Target", formatter.format(targetPayment), color: Colors.green),
            _buildSummaryRow("Required Overpayment", formatter.format(reqOverpay), color: Colors.orange),
            const Divider(height: 15),
            _buildSummaryRow("10% Cap Status", capStatus),
          ],
        ),
      ),
    );
  }
  
  Widget _buildChart() {
    if (_chartData.isEmpty) return const Center(child: Text("Run calculation to view chart data."));
    
    final balances = _chartData.map((e) => e.balance).toList();
    if (balances.every((b) => b == 0.0)) {
       return const Center(child: Text("Chart data is all zeros. Check inputs."));
    }
    
    double maxY = balances.reduce((a, b) => a > b ? a : b);
    double maxX = _chartData.map((e) => e.month.toDouble()).reduce((a, b) => a > b ? a : b);
    
    if (maxY == 0) maxY = 1;

    // Single line chart
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
                leftTitles: AxisTitles(axisNameWidget: const Text('Balance (£)'),
                  sideTitles: SideTitles(getTitlesWidget: (v, m) => Text('£${(v / 1000).toInt()}k'), reservedSize: 40, interval: maxY / 4)),
                bottomTitles: AxisTitles(axisNameWidget: const Text('Months'),
                  sideTitles: SideTitles(getTitlesWidget: (v, m) => SideTitleWidget(axisSide: m.axisSide, space: 8.0, child: Text(v.toInt().toString())), reservedSize: 30, interval: 60)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(spots: _chartData.map((data) => FlSpot(data.month.toDouble(), data.balance)).toList(), isCurved: true, color: Colors.blue.shade800, barWidth: 2, dotData: const FlDotData(show: false)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleTable() {
    if (_yearlySchedule.isEmpty) return const Center(child: Text("Run calculation to view the amortization schedule."));
    
    final List<Object> data = _isMonthlyView ? _monthlySchedule : _yearlySchedule;
    final currencySymbol = '£'; 
    
    List<DataColumn> columns = _isMonthlyView 
      ? [
          const DataColumn(label: Text('Month', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Payment ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
          DataColumn(label: Text('Principal ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
          DataColumn(label: Text('Interest ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
          DataColumn(label: Text('Balance ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
        ] 
      : [
          const DataColumn(label: Text('Year', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Payment ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
          DataColumn(label: Text('Principal ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
          DataColumn(label: Text('Interest ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
          DataColumn(label: Text('Balance ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
        ];

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
                    Switch(value: _isMonthlyView, onChanged: (value) => setState(() => _isMonthlyView = value), activeThumbColor: Colors.blue),
                  ],
                ),
              ],
            ),
            const Divider(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: columns,
                rows: data.map((item) {
                  dynamic row = _isMonthlyView ? item as MonthlyScheduleRow : item as YearlyScheduleRow;
                  return DataRow(
                    cells: [
                      DataCell(Text(_isMonthlyView ? row.month.toString() : (row.year == 0 ? '0 (Start)' : row.year.toString()))),
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
            const Text("Required Overpayment Calculator", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 20),

            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Input", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blue)),
                    const SizedBox(height: 10),
                    _buildTextField(loanController, 'Loan Amount (£)', icon: Icons.currency_pound),
                    _buildTextField(rateController, 'Annual Interest Rate (%)', icon: Icons.percent),
                    _buildTextField(currentYearsController, 'Current Remaining Years', icon: Icons.calendar_today),
                    _buildTextField(targetTimeController, 'Target Payoff Time (Years)', icon: Icons.calendar_month),
                    const Divider(height: 20),
                    _buildTextField(requiredPaymentController, 'Required Monthly Payment (£)', icon: Icons.payments, readOnly: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            ElevatedButton.icon(
              onPressed: _simulate,
              icon: const Icon(Icons.calculate),
              label: const Text("Calculate Required Payment"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            
            _buildSummaryCard(),
            
            const SizedBox(height: 20),
            
            const Text("Amortization Balance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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