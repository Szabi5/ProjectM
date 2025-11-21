// lib/screens/refinance_screen.dart
//
// UPDATED: Removed 'final' keyword from commonInputDecoration
// helper function inside the build method.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';

import '../services/python_bridge.dart';
import '../utils/refinance_export.dart';

// --- Data Model ---
class MonthlyScheduleRow {
  final int month;
  final double payment;
  final double principal;
  final double interest;
  final double balance;

  MonthlyScheduleRow.fromJson(Map<String, dynamic> json)
      : month = (json['month'] ?? json['Month'] ?? 0).toInt(),
        payment = (json['payment'] ?? json['Payment'] ?? 0.0).toDouble(),
        principal = (json['principal'] ?? json['Principal'] ?? 0.0).toDouble(),
        interest = (json['interest'] ?? json['Interest'] ?? 0.0).toDouble(),
        balance = (json['balance'] ?? json['Balance'] ?? 0.0).toDouble();
}

class RefinanceScreen extends StatefulWidget {
  const RefinanceScreen({Key? key}) : super(key: key);

  @override
  State<RefinanceScreen> createState() => _RefinanceScreenState();
}

class _RefinanceScreenState extends State<RefinanceScreen> with SingleTickerProviderStateMixin {
  final bridge = FlutterPythonBridge();

  final _loanC = TextEditingController();
  final _rateC = TextEditingController();
  final _yearsC = TextEditingController();
  final _feesC = TextEditingController();
  final _refRateC = TextEditingController();
  final _monthsElapsedC = TextEditingController(text: '0');

  bool _isLoading = false;
  String? _errorText;
  Map<String, dynamic> _rawResult = {};
  
  List<MonthlyScheduleRow> _baseline = [];
  List<MonthlyScheduleRow> _refinance = [];
  
  int? _breakEven = null;
  double _fees = 0.0;
  double _interestSaved = 0.0;
  double _baselineTotalInterest = 0.0;
  double _refinanceTotalInterest = 0.0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loanC.dispose();
    _rateC.dispose();
    _yearsC.dispose();
    _feesC.dispose();
    _refRateC.dispose();
    _monthsElapsedC.dispose();
    super.dispose();
  }

  Widget _buildSummaryCard() {
    if (_rawResult.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fees: £${_fees.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 6),
          Text('Break-even: ${_breakEven == null ? "Not within compared term" : "$_breakEven months"}',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 6),
          Text('Baseline total interest: £${_baselineTotalInterest.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Text('Refinance total interest (+ fees): £${_refinanceTotalInterest.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            'Estimated interest saved: £${_interestSaved.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 16,
              color: _interestSaved > 0 ? Colors.green.shade600 : Colors.red.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildScheduleTable(List<MonthlyScheduleRow> data) {
    if (data.isEmpty) {
      return const Center(
        heightFactor: 5, 
        child: Text("Run analysis to see schedule.")
      );
    }

    final currencySymbol = '£'; 
    
    List<DataColumn> columns = [
      const DataColumn(label: Text('Month', style: TextStyle(fontWeight: FontWeight.bold))),
      DataColumn(label: Text('Payment ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
      DataColumn(label: Text('Principal ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
      DataColumn(label: Text('Interest ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
      DataColumn(label: Text('Balance ($currencySymbol)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right), numeric: true),
    ];
    
    List<DataRow> rows = data.map((row) {
      return DataRow(
        cells: [
          DataCell(Text(row.month.toString())),
          DataCell(Text(row.payment.toStringAsFixed(2))),
          DataCell(Text(row.principal.toStringAsFixed(2))),
          DataCell(Text(row.interest.toStringAsFixed(2))),
          DataCell(Text(row.balance.toStringAsFixed(2), style: TextStyle(fontWeight: row.balance <= 0.01 ? FontWeight.bold : FontWeight.normal))),
        ]
      );
    }).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            dataRowMinHeight: 30,
            dataRowMaxHeight: 40,
            headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
            columns: columns,
            rows: rows,
          ),
        ),
      ),
    );
  }


  Future<void> _runAnalysis() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
      _rawResult = {};
      _baseline = [];
      _refinance = [];
      _breakEven = null;
    });

    final Map<String, dynamic> payload = {
      'current': {
        'loan': double.tryParse(_loanC.text) ?? 0.0,
        'rate': double.tryParse(_rateC.text) ?? 0.0,
        'years': int.tryParse(_yearsC.text) ?? 0,
      },
      'refinance': {
        'rate': double.tryParse(_refRateC.text) ?? double.tryParse(_rateC.text) ?? 0.0,
        'years': int.tryParse(_yearsC.text) ?? 0,
        'fees': double.tryParse(_feesC.text) ?? 0.0,
      },
      'months_elapsed': int.tryParse(_monthsElapsedC.text) ?? 0
    };

    try {
      final resString = await bridge.run("Refinance analysis", payload);
      final Map<String, dynamic> res = jsonDecode(resString) as Map<String, dynamic>;

      if (res.containsKey('error')) {
        setState(() {
          _isLoading = false;
          _errorText = res['error'].toString();
        });
        return;
      }

      setState(() {
        _rawResult = res;
        _baseline = (res['baseline_monthly'] as List<dynamic>? ?? []).map((e) => MonthlyScheduleRow.fromJson(e as Map<String, dynamic>)).toList();
        _refinance = (res['refinance_monthly'] as List<dynamic>? ?? []).map((e) => MonthlyScheduleRow.fromJson(e as Map<String, dynamic>)).toList();
        _breakEven = res['break_even_month'] is num ? (res['break_even_month'] as num).toInt() : null;
        _fees = (res['fees'] as num?)?.toDouble() ?? 0.0;
        _baselineTotalInterest = (res['baseline_total_interest'] as num?)?.toDouble() ?? 0.0;
        _refinanceTotalInterest = (res['refinance_total_interest'] as num?)?.toDouble() ?? 0.0;
        _interestSaved = (res['interest_saved'] as num?)?.toDouble() ?? 0.0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorText = 'Failed to run analysis: $e';
      });
    }
  }

  Future<void> _exportRefinanceExcel() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final payload = {
        'current': {
          'loan': double.tryParse(_loanC.text) ?? 0.0,
          'rate': double.tryParse(_rateC.text) ?? 0.0,
          'years': int.tryParse(_yearsC.text) ?? 0,
        },
        'refinance': {
          'rate': double.tryParse(_refRateC.text) ?? double.tryParse(_rateC.text) ?? 0.0,
          'years': int.tryParse(_yearsC.text) ?? 0,
          'fees': double.tryParse(_feesC.text) ?? 0.0,
        },
        'months_elapsed': int.tryParse(_monthsElapsedC.text) ?? 0
      };

      final savedPath = await exportAndSaveRefinanceExcel(bridge, payload);

      setState(() {
        _errorText = "Export finished: $savedPath";
      });

      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Refinance Excel exported'),
          content: Text('Saved to:\n$savedPath'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            TextButton(onPressed: () async { Navigator.of(context).pop(); await OpenFile.open(savedPath); }, child: const Text('Open file')),
            TextButton(onPressed: () async { Navigator.of(context).pop(); await Share.shareXFiles([XFile(savedPath)], text: 'Refinance analysis exported'); }, child: const Text('Share')),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _errorText = 'Export failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    //
    // --- THIS IS THE FIX ---
    // Removed the 'final' keyword from the function definition
    //
    InputDecoration commonInputDecoration({
      required String labelText,
      String? prefixText,
      IconData? prefixIcon,
    }) {
      return InputDecoration(
        labelText: labelText,
        labelStyle: Theme.of(context).textTheme.titleSmall, // Adjust to match your theme
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
        prefixIcon: prefixIcon != null ? SizedBox(
          width: 40,
          child: Center(
            child: Icon(prefixIcon, color: Theme.of(context).hintColor, size: 20),
          ),
        ) : null,
        prefixText: prefixText,
        prefixStyle: Theme.of(context).textTheme.titleMedium, // Style for €, %
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      );
    }
    // --- END OF FIX ---

    return Scaffold(
      appBar: AppBar(
        title: const Text('Refinance analysis'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Loan Details', style: Theme.of(context).textTheme.headlineSmall),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextField(
                          controller: _loanC,
                          keyboardType: TextInputType.number,
                          decoration: commonInputDecoration(
                            labelText: 'Loan amount',
                            prefixText: '€ ', // Assuming € for this example
                          ),
                        ),
                        const SizedBox(height: 12), 
                        TextField(
                          controller: _rateC,
                          keyboardType: TextInputType.number,
                          decoration: commonInputDecoration(
                            labelText: 'Rate',
                            prefixText: '% ',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _refRateC,
                          keyboardType: TextInputType.number,
                          decoration: commonInputDecoration(
                            labelText: 'Refinance rate (leave blank to use current)',
                            prefixText: '% ',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _yearsC,
                          keyboardType: TextInputType.number,
                          decoration: commonInputDecoration(
                            labelText: 'Remaining years',
                            prefixIcon: Icons.calendar_today,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _feesC,
                          keyboardType: TextInputType.number,
                          decoration: commonInputDecoration(
                            labelText: 'Fees / Closing costs',
                            prefixText: '€ ', // Assuming €
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _monthsElapsedC,
                          keyboardType: TextInputType.number,
                          decoration: commonInputDecoration(
                            labelText: 'Months elapsed (0 = now)',
                            prefixIcon: Icons.date_range,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _runAnalysis,
                    icon: _isLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow),
                    label: Text(_isLoading ? 'Running...' : 'Run analysis'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8.0, 
                  runSpacing: 8.0,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _exportRefinanceExcel,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Export Excel'),
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: (_baseline.isNotEmpty) ? () { /* export baseline csv existing */ } : null,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Baseline CSV'),
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: (_refinance.isNotEmpty) ? () { /* export refinance csv existing */ } : null,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Refinance CSV'),
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(_errorText!, style: const TextStyle(color: Colors.red)),
                ],

                if (!_isLoading) _buildSummaryCard(),

                const SizedBox(height: 8),

                _isLoading
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ))
                    : Column(
                        children: [
                          TabBar(
                            controller: _tabController,
                            labelColor: Theme.of(context).primaryColor,
                            unselectedLabelColor: Colors.grey,
                            tabs: const [
                              Tab(text: 'Baseline Schedule'),
                              Tab(text: 'Refinance Schedule'),
                            ],
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 400, 
                            ),
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildScheduleTable(_baseline),
                                _buildScheduleTable(_refinance),
                              ],
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}