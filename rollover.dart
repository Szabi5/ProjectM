// lib/screens/rollover.dart

import 'package:flutter/material.dart';
import '../services/python_bridge.dart';
import 'dart:convert';

// --- Data Models (for Rollover Comparison) ---

class RolloverChartData {
  final int month;
  final double option1Balance;
  final double option2Balance;
  
  RolloverChartData(this.month, this.option1Balance, this.option2Balance);
  
  factory RolloverChartData.fromJson(Map<String, dynamic> json) {
    return RolloverChartData(
      json['month'] as int,
      (json['option1_balance'] as num).toDouble(),
      (json['option2_balance'] as num).toDouble(), 
    );
  }
}

// Re-using the schedule row models (assuming they exist in your file)
class YearlyScheduleRow {
  final int year;
  final double payment;
  final double principal;
  final double interest;
  final double balance;

  YearlyScheduleRow.fromJson(Map<String, dynamic> json)
      : year = json['year'] as int,
        payment = (json['payment'] as num).toDouble(),
        principal = (json['principal'] as num).toDouble(),
        interest = (json['interest'] as num).toDouble(),
        balance = (json['balance'] as num).toDouble();
}

class MonthlyScheduleRow {
  final int month;
  final double payment;
  final double principal;
  final double interest;
  final double balance;

  MonthlyScheduleRow.fromJson(Map<String, dynamic> json)
      : month = json['month'] as int,
        payment = (json['payment'] as num).toDouble(),
        principal = (json['principal'] as num).toDouble(),
        interest = (json['interest'] as num).toDouble(),
        balance = (json['balance'] as num).toDouble();
}

class RolloverScreen extends StatefulWidget {
  const RolloverScreen({super.key});
  @override
  State<RolloverScreen> createState() => _RolloverScreenState();
}

class _RolloverScreenState extends State<RolloverScreen> {
  final bridge = FlutterPythonBridge();
  String _result = "Enter details and click 'Simulate'."; 
  List<RolloverChartData> _chartData = []; 
  List<YearlyScheduleRow> _yearlySchedule = []; 
  List<MonthlyScheduleRow> _monthlySchedule = []; 
  
  bool _isMonthlyView = false; 
  Map<String, dynamic>? _summaryData; 

  // --- Controllers (assuming necessary fields for a two-option comparison) ---
  final loanController = TextEditingController();
  final rate1Controller = TextEditingController(); 
  final term1Controller = TextEditingController(); 
  final rate2Controller = TextEditingController(); 
  final term2Controller = TextEditingController(); 

  late final Map<String, TextEditingController> _controllers = {
    'loan': loanController, 'rate1': rate1Controller, 'term1': term1Controller,
    'rate2': rate2Controller, 'term2': term2Controller,
  };
  
  // ... (initState, _loadSettings, _saveSettings, dispose methods similar to other screens) ...

  // --- Simulation Logic (Placeholder/Mock logic) ---
  void _simulate() async {
    final inputData = {
      'loan_amount': double.tryParse(loanController.text) ?? 0.0,
      'rate1': double.tryParse(rate1Controller.text) ?? 0.0,
      'term1': int.tryParse(term1Controller.text) ?? 0,
      'rate2': double.tryParse(rate2Controller.text) ?? 0.0,
      'term2': int.tryParse(term2Controller.text) ?? 0,
    };
    final jsonInput = jsonEncode(inputData);

    setState(() {
      _result = "Running simulation..."; _chartData = []; _yearlySchedule = [];
      _monthlySchedule = []; _summaryData = null; 
    });
    
    // Using the 'rollover simulation' identifier
    final resString = await bridge.run("Mortgage rollover simulation", jsonInput); 
    
    try {
      final resData = jsonDecode(resString) as Map<String, dynamic>;
      
      // Assuming the structure is similar, but the Python logic may be placeholder
      _chartData = (resData['chart_data'] as List<dynamic>?)?.map((item) => RolloverChartData.fromJson(item as Map<String, dynamic>)).toList() ?? [];
      
      if (resData.containsKey('structured_summary') && resData['structured_summary'] is Map) {
        _summaryData = resData['structured_summary'] as Map<String, dynamic>;
        _result = "Simulation completed."; 
      } else {
        _result = resData['summary'] ?? "Error: Could not parse structured summary.";
      }
      
      // Mocking schedule data if Python output is not yet structured for it
      // Replace this with actual parsing if your Python function returns schedules
      _yearlySchedule = []; 
      _monthlySchedule = [];

      setState(() {});

    } catch (e) {
      setState(() => _result = "API Error: Could not parse JSON response: $e\nRaw output:\n$resString");
    }
  }

  // --- Widget Builders (Assuming _buildTextField exists here too) ---

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

  // ... (Other helper widgets: _buildSummaryCard, _buildChart) ...

  Widget _buildScheduleTable() {
    if (_yearlySchedule.isEmpty && _monthlySchedule.isEmpty) return const Center(child: Text("Run simulation to view the amortization schedule."));
    
    final List<Object> data = _isMonthlyView ? _monthlySchedule : _yearlySchedule;
    final currencySymbol = '£'; 
    
    // FIX 3: Removed invalid 'name' parameter from DataColumn
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

    // ... (DataTable implementation) ...
    // Note: Assuming the rest of your table rendering logic works,
    // this block focuses on the corrected column definitions.
    return Card(
      child: Center(
        child: Text("Rollover Schedule Placeholder - Column definitions fixed."),
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
            const Text("Mortgage Rollover Comparison", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 20),

            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(loanController, 'Current Loan Amount (£)', icon: Icons.currency_pound),
                    const Divider(),
                    const Text("Option 1 (e.g., Stay with current lender)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blue)),
                    _buildTextField(rate1Controller, 'Rate Option 1 (%)', icon: Icons.percent),
                    _buildTextField(term1Controller, 'Term Option 1 (Years)', icon: Icons.calendar_month),
                    const Divider(),
                    const Text("Option 2 (e.g., Switch to new lender)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.green)),
                    _buildTextField(rate2Controller, 'Rate Option 2 (%)', icon: Icons.percent),
                    _buildTextField(term2Controller, 'Term Option 2 (Years)', icon: Icons.calendar_month),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            ElevatedButton.icon(
              onPressed: _simulate,
              icon: const Icon(Icons.compare),
              label: const Text("Compare Rollover Options"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            
            // ... (Summary Card, Chart, and Schedule Table calls) ...
            
          ],
        ),
      ),
    );
  }
}