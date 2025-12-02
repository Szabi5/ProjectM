// lib/screens/uk_mortgage.dart

import 'package:flutter/material.dart';
import '../services/python_bridge.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:intl/intl.dart'; 
import '../utils/pdf_generator.dart'; // <--- NEW IMPORT
import '../models/report_data.dart';

// --- Data Models (NULL-SAFE) ---

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


class UkMortgageScreen extends StatefulWidget {
  const UkMortgageScreen({super.key});
  @override
  State<UkMortgageScreen> createState() => _UkMortgageScreenState();
}

class _UkMortgageScreenState extends State<UkMortgageScreen> {
  final bridge = FlutterPythonBridge();
  String _result = "Enter details and click 'Run Projection'."; 
  List<MortgageChartData> _chartData = []; 
  List<YearlyScheduleRow> _yearlySchedule = []; 
  List<MonthlyScheduleRow> _monthlySchedule = []; 
  
  // NEW STATE: Store the raw monthly schedule data (List<Map>) for PDF export
  List<Map<String, dynamic>> _fullMonthlySchedule = [];
  
  bool _isMonthlyView = false; 
  Map<String, dynamic>? _summaryData; 

  // --- Controllers ---
  final loanController = TextEditingController();
  final rateController = TextEditingController();
  final yearsController = TextEditingController();
  final valueController = TextEditingController(); 
  final overpayController = TextEditingController(); 
  final extraPctController = TextEditingController(); 
  final lumpSumController = TextEditingController(); 
  final lumpMonthController = TextEditingController(); 
  final oneOffSumController = TextEditingController(); 
  final oneOffMonthController = TextEditingController(); 
  final inflationController = TextEditingController();
  final rateChangesController = TextEditingController();

  late final Map<String, TextEditingController> _controllers = {
    'loan': loanController, 'rate': rateController, 'years': yearsController,
    'value': valueController, 'overpay': overpayController, 'extraPct': extraPctController,
    'lumpSum': lumpSumController, 'lumpMonth': lumpMonthController, 
    'oneOffSum': oneOffSumController, 'oneOffMonth': oneOffMonthController, 
    'inflation': inflationController, 'rateChanges': rateChangesController,
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
      await prefs.setString('uk_mortgage_${entry.key}', entry.value.text);
    }
    setState(() {
      _result = "✅ Settings saved successfully!";
    });
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final defaults = {
      'loan': '152819.71', 'rate': '4.69', 'years': '24', 'value': '318000.0', 
      'overpay': '0', 'extraPct': '0', 'lumpSum': '0', 'lumpMonth': '12', 
      'oneOffSum': '0', 'oneOffMonth': '0', 'inflation': '0.0', 'rateChanges': ''
    };

    for (var entry in _controllers.entries) {
      final value = prefs.getString('uk_mortgage_${entry.key}') ?? defaults[entry.key] ?? '';
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

  // --- Simulation Logic (with CORRECTED JSON keys) ---
  void _simulate() async {
    final inputData = {
      'loan': double.tryParse(loanController.text) ?? 0.0,
      'rate': double.tryParse(rateController.text) ?? 0.0,
      'years': int.tryParse(yearsController.text) ?? 0,
      'value': double.tryParse(valueController.text) ?? 0.0,
      'monthly_overpay': double.tryParse(overpayController.text) ?? 0.0,
      'overpay_pct_of_base': double.tryParse(extraPctController.text) ?? 0.0,
      'annual_lump': double.tryParse(lumpSumController.text) ?? 0.0,
      'annual_lump_month': int.tryParse(lumpMonthController.text) ?? 12,
      'one_off_lump': double.tryParse(oneOffSumController.text) ?? 0.0,
      'one_off_lump_month': int.tryParse(oneOffMonthController.text) ?? 0,
      'inflation': double.tryParse(inflationController.text) ?? 0.0,
      'rate_changes': rateChangesController.text,
    };
    
    print("DART IS SENDING (UK): ${jsonEncode(inputData)}");

    setState(() {
      _result = "Running simulation...";
      _chartData = []; 
      _yearlySchedule = [];
      _monthlySchedule = []; 
      _summaryData = null; 
      _fullMonthlySchedule = []; // Clear old schedule
    });
    
    // Pass the 'inputData' map directly
    final resString = await bridge.run("UK mortgage simulation", inputData); 
    
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
        // Store MonthlyScheduleRow objects
        _monthlySchedule = (resData['monthly_schedule'] as List<dynamic>)
            .map((item) => MonthlyScheduleRow.fromJson(item as Map<String, dynamic>))
            .toList();
            
        // Store raw Map<String, dynamic> objects for PDF generation
        _fullMonthlySchedule = (resData['monthly_schedule'] as List<dynamic>)
            .cast<Map<String, dynamic>>(); 
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
  
  // --- NEW: PDF Export Function ---
  void _exportReport() async {
    if (_summaryData == null || _fullMonthlySchedule.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please run the projection first.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _result = "Generating PDF...";
    });
    
    // Create the data object for the generator
    final reportData = ReportData(
      reportTitle: "UK Mortgage Projection Report",
      summary: _summaryData!,
      monthlySchedule: _fullMonthlySchedule,
      currencySymbol: '£',
    );
    
    try {
      final pdfBytes = await generateReport(reportData);
      
      // Opens the native share dialog or PDF viewer
      Future.microtask(() {
        viewPdf(context, pdfBytes, 'UK_Mortgage_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
      });

      setState(() {
        _result = "PDF Generated!";
      });
      
    } catch (e) {
      setState(() {
        _result = "PDF Export Failed: ${e.toString()}";
      });
    }
  }


  // --- Widget Builders (unchanged unless noted) ---
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
// ... (rest of _buildSummaryCard and _buildChart are unchanged) ...
  Widget _buildSummaryCard() {
    if (_summaryData == null) {
      return Text(_result);
    }
    
    final formatter = NumberFormat.currency(locale: 'en_GB', symbol: '£');
    final percentFormatter = NumberFormat.percentPattern('en_GB');
    
    final basePayment = _summaryData!['base_monthly_payment'];
    final overpayPayment = _summaryData!['overpay_monthly_payment'];
    final timeSaved = _summaryData!['time_saved_years'];
    final interestSaved = _summaryData!['interest_saved'];
    final ltv = _summaryData!['ltv_pct'];

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
            const Text("Mortgage Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(),
            
            _buildSummaryRow("Base Monthly Payment", formatter.format(basePayment)),
            _buildSummaryRow("Total Monthly Payment", formatter.format(overpayPayment), color: Colors.green),
            
            const Divider(height: 15),
            
            _buildSummaryRow("Time Saved", "${timeSaved.toStringAsFixed(1)} years", color: Colors.red),
            _buildSummaryRow("Interest Saved", formatter.format(interestSaved), color: Colors.red),
            
            const Divider(height: 15),

            _buildSummaryRow("Loan-to-Value (LTV)", ltv == "N/A" ? "N/A" : percentFormatter.format(ltv / 100)),
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
            const Text("UK Mortgage Calculator", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
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
                    _buildTextField(valueController, 'Property Value (£)', icon: Icons.home),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Overpayment Strategies", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.green)),
                    const SizedBox(height: 10),
                    _buildTextField(overpayController, 'Monthly Overpayment (£)', icon: Icons.payments),
                    _buildTextField(extraPctController, '% of Base Monthly (extra)', icon: Icons.trending_up),
                    _buildTextField(lumpSumController, 'Annual Lump Sum (£)', icon: Icons.account_balance),
                    _buildTextField(lumpMonthController, 'Annual Lump Month (1-12)', icon: Icons.date_range),
                    _buildTextField(oneOffSumController, 'One-off Lump Sum (£)', icon: Icons.attach_money),
                    _buildTextField(oneOffMonthController, 'One-off Lump Month (0=off)', icon: Icons.event),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Rates & Inflation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.orange)),
                    const SizedBox(height: 10),
                    _buildTextField(rateChangesController, 'Rate changes (e.g. 12:4.5, 24:6)', icon: Icons.timeline),
                    _buildTextField(inflationController, 'Inflation % (optional)', icon: Icons.bar_chart),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
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
                    onPressed: _exportReport, // <--- PDF EXPORT BUTTON
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text("Export PDF"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700, 
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