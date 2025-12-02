// lib4.zip/screens/savings_growth_screen.dart

import 'package:flutter/material.dart';
import '../services/python_bridge.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:intl/intl.dart'; 
import 'package:fl_chart/fl_chart.dart'; 

// --- Data Models for Growth ---
class GrowthPoint {
  final int period; // Month or Year
  final double balance;
  
  GrowthPoint(this.period, this.balance);
  
  factory GrowthPoint.fromJson(Map<String, dynamic> json) {
    return GrowthPoint(
      (json['period'] as num? ?? 0).toInt(),
      (json['balance'] as num? ?? 0.0).toDouble(),
    );
  }
}

class SavingsGrowthScreen extends StatefulWidget {
  const SavingsGrowthScreen({super.key});
  @override
  State<SavingsGrowthScreen> createState() => _SavingsGrowthScreenState();
}

class _SavingsGrowthScreenState extends State<SavingsGrowthScreen> {
  final bridge = FlutterPythonBridge();
  
  // Controllers
  final initialBalanceController = TextEditingController(text: '1000');
  final monthlyContributionController = TextEditingController(text: '200');
  final annualRateController = TextEditingController(text: '2.0');
  final yearsController = TextEditingController(text: '10');
  
  String _frequency = 'Monthly'; 
  String _resultMessage = "Enter details and calculate.";
  List<GrowthPoint> _chartData = [];
  
  // NEW STATE VARIABLE for toggle
  bool _isMonthlyView = false; 
  
  // --- Lifecycle and Persistence (Simplified) ---
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    initialBalanceController.text = prefs.getString('savings_initial_balance') ?? '1000';
    monthlyContributionController.text = prefs.getString('savings_contribution') ?? '200';
    annualRateController.text = prefs.getString('savings_rate') ?? '2.0';
    yearsController.text = prefs.getString('savings_years') ?? '10';
    _frequency = prefs.getString('savings_frequency') ?? 'Monthly';
    setState(() {});
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savings_initial_balance', initialBalanceController.text);
    await prefs.setString('savings_contribution', monthlyContributionController.text);
    await prefs.setString('savings_rate', annualRateController.text);
    await prefs.setString('savings_years', yearsController.text);
    await prefs.setString('savings_frequency', _frequency);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Settings saved!'), backgroundColor: Colors.green),
    );
  }

  @override
  void dispose() {
    initialBalanceController.dispose();
    monthlyContributionController.dispose();
    annualRateController.dispose();
    yearsController.dispose();
    super.dispose();
  }
  
  // --- Calculation Logic ---
  void _calculateGrowth() async {
    final inputData = {
      'initial_balance': double.tryParse(initialBalanceController.text) ?? 0.0,
      'contribution_amount': double.tryParse(monthlyContributionController.text) ?? 0.0,
      'annual_rate': double.tryParse(annualRateController.text) ?? 0.0,
      'years': int.tryParse(yearsController.text) ?? 0,
      'frequency': _frequency.toLowerCase(),
    };
    
    setState(() {
      _resultMessage = "Calculating...";
      _chartData = [];
    });

    final resString = await bridge.run("savings growth calculation", inputData);
    
    try {
      final resData = jsonDecode(resString) as Map<String, dynamic>;

      if (resData.containsKey('error')) {
        setState(() {
          _resultMessage = "Calculation Error: ${resData['error']}";
        });
        return;
      }
      
      _chartData = (resData['history'] as List<dynamic>?)
          ?.map((item) => GrowthPoint.fromJson(item as Map<String, dynamic>))
          .toList() ?? [];
      
      // Handle case where history is empty (e.g., 0 years)
      final finalBalance = _chartData.isNotEmpty ? _chartData.last.balance : inputData['initial_balance'] as double;
      
      setState(() {
        _resultMessage = "Final Balance after ${inputData['years']} years: ${NumberFormat.currency(symbol: '£').format(finalBalance)}";
      });

    } catch (e) {
      setState(() => _resultMessage = "API Error: Could not parse response: $e");
    }
  }
  
  // --- Widget Builders ---

  Widget _buildTextField(TextEditingController controller, String label, {IconData? icon, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          suffixText: suffix,
          border: const OutlineInputBorder(),
          isDense: true, 
        ),
      ),
    );
  }

  Widget _buildGrowthTable() {
    if (_chartData.isEmpty) return const Center(child: Text("Run calculation to view schedule."));

    // Determine which data to display
    final List<GrowthPoint> dataToDisplay = _isMonthlyView 
        ? _chartData 
        : _chartData.where((p) => p.period % 12 == 0).toList();
    
    // Determine column headers
    final String periodLabel = _isMonthlyView ? 'Month' : 'Year';
    final int periodFactor = _isMonthlyView ? 1 : 12;

    final currencyFormat = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);

    final List<DataRow> rows = dataToDisplay.map((point) {
      // Use integer division to show years (e.g., 12 months = 1 year)
      final displayPeriod = (point.period / periodFactor).round(); 
      
      return DataRow(
        cells: [
          DataCell(Text(displayPeriod.toString())),
          DataCell(Text(currencyFormat.format(point.balance))),
        ]
      );
    }).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- ADD TOGGLE SWITCH (Main difference from previous version) ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Growth Schedule", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Text(_isMonthlyView ? 'Monthly View' : 'Yearly View'),
                    Switch(
                      value: _isMonthlyView,
                      onChanged: (value) => setState(() => _isMonthlyView = value),
                      activeThumbColor: Theme.of(context).primaryColor,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            // --- END TOGGLE SWITCH ---
            
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(periodLabel, style: const TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Balance (£)', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_chartData.isEmpty) return const SizedBox.shrink();
    
    final maxX = _chartData.last.period.toDouble();
    final maxY = _chartData.map((p) => p.balance).reduce((a, b) => a > b ? a : b);

    final spots = _chartData.map((p) => FlSpot(p.period.toDouble(), p.balance)).toList();

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
                leftTitles: AxisTitles(
                  axisNameWidget: const Text('Balance (£)'),
                  sideTitles: SideTitles(
                    getTitlesWidget: (v, m) => Text('£${(v / 1000).toInt()}k'), reservedSize: 40, interval: maxY / 4
                  )),
                bottomTitles: AxisTitles(
                  axisNameWidget: const Text('Months'),
                  sideTitles: SideTitles(
                    getTitlesWidget: (v, m) => SideTitleWidget(axisSide: m.axisSide, space: 8.0, child: Text((v~/12).toInt().toString())), reservedSize: 30, interval: 120 // Every 10 years
                  )),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots, 
                  isCurved: true, 
                  color: Colors.blue.shade600, 
                  barWidth: 3, 
                  dotData: const FlDotData(show: false)),
              ],
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Savings Growth Projector", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 20),

            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Savings Parameters", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blue)),
                    const SizedBox(height: 10),
                    _buildTextField(initialBalanceController, 'Initial Balance (£)', icon: Icons.attach_money),
                    _buildTextField(monthlyContributionController, 'Contribution Amount (£)', icon: Icons.add_circle),
                    
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _frequency,
                            decoration: const InputDecoration(
                              labelText: 'Frequency',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                              DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                            ],
                            onChanged: (value) => setState(() => _frequency = value!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _buildTextField(annualRateController, 'Annual Rate (%)', icon: Icons.percent)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(yearsController, 'Projection Years', icon: Icons.calendar_month, suffix: 'Years'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            ElevatedButton.icon(
              onPressed: _calculateGrowth,
              icon: const Icon(Icons.calculate),
              label: const Text("Project Future Value"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            
            Text(_resultMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
            
            const SizedBox(height: 20),
            
            _buildChart(),

            const SizedBox(height: 20),
            
            _buildGrowthTable(),

            const SizedBox(height: 20),
            
            ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.settings),
              label: const Text("Save Settings"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade400,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}