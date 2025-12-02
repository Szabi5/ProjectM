// lib/screens/rollover_tab.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../services/python_bridge.dart';
import '../utils/rollover_export.dart';

class RolloverTab extends StatefulWidget {
  const RolloverTab({Key? key}) : super(key: key);

  @override
  _RolloverTabState createState() => _RolloverTabState();
}

class _RolloverTabState extends State<RolloverTab> {
  final _pythonPlugin = FlutterPythonBridge();
  bool _isLoading = false;

  final _conversionRateC = TextEditingController(text: "0.85");

  String _errorText = "";
  // EUR
  String _eurPayoffTime = "";
  String _eurFreedPayment = "";
  String _eurBaselineInterest = "";
  String _eurOverpayInterest = "";
  String _eurInterestSaved = "";
  // UK Baseline
  String _ukBaselinePayoff = "";
  String _ukRemainingTerm = "";
  String _ukBaselineInterest = "";
  // UK Rollover
  String _ukBalanceAtRollover = "";
  String _ukExtraMonthly = "";
  String _ukAnnualPct = "";
  String _ukPayoffAfterRollover = "";
  String _ukTotalInterestRollover = "";
  String _ukInterestSaved = "";
  // Comparison
  String _compBaseline = "";
  String _compWithRollover = "";
  String _compTimeSaved = "";
  String _totalMortgageFreeTime = "";

  // --- NEW: Load the automated rate on startup ---
  @override
  void initState() {
    super.initState();
    _loadGlobalSettings();
  }

  // --- NEW: Fetch rate from SharedPreferences ---
  Future<void> _loadGlobalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // This key matches what we set in snapshot_screen.dart
    final savedRate = prefs.getString('snapshot_conversion_rate');
    
    if (savedRate != null && savedRate.isNotEmpty) {
      setState(() {
        _conversionRateC.text = savedRate;
      });
    }
  }

  @override
  void dispose() {
    _conversionRateC.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadMortgageData(SharedPreferences prefs, String prefix) async {
    final keys = [
      'loan', 'rate', 'years', 'value', 'overpay', 'extraPct',
      'lumpSum', 'lumpMonth', 'oneOffSum', 'oneOffMonth', 'inflation', 'rateChanges'
    ];
    Map<String, dynamic> data = {};
    for (var key in keys) {
      String? value = prefs.getString('${prefix}_$key');
      String pythonKey;
      switch (key) {
        case 'overpay':
          pythonKey = 'monthly_overpay';
          break;
        case 'extraPct':
          pythonKey = 'overpay_pct_of_base';
          break;
        case 'lumpSum':
          pythonKey = 'annual_lump';
          break;
        case 'lumpMonth':
          pythonKey = 'annual_lump_month';
          break;
        case 'oneOffSum':
          pythonKey = 'one_off_lump';
          break;
        case 'oneOffMonth':
          pythonKey = 'one_off_lump_month';
          break;
        case 'rateChanges':
          pythonKey = 'rate_changes';
          break;
        default:
          pythonKey = key;
      }
      data[pythonKey] = double.tryParse(value ?? '0.0') ?? (value ?? '');
    }
    return data;
  }

  Future<void> _runRolloverSimulation() async {
    setState(() {
      _isLoading = true;
      _errorText = "";
      _clearResults();
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final eurData = await _loadMortgageData(prefs, 'eu_mortgage');
      final gbpData = await _loadMortgageData(prefs, 'uk_mortgage');

      final dataToSend = {
        'eur_data': eurData,
        'gbp_data': gbpData,
        'conversion_rate': double.tryParse(_conversionRateC.text) ?? 0.85
      };

      print("DART IS SENDING (Rollover): ${jsonEncode(dataToSend)}");

      final responseString = await _pythonPlugin.run("rollover simulation", dataToSend);
      _processRolloverResponse(responseString);
    } catch (e) {
      setState(() {
        _errorText = "Failed to run script: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportRolloverExcel() async {
    setState(() {
      _isLoading = true;
      _errorText = "";
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final eurData = await _loadMortgageData(prefs, 'eu_mortgage');
      final gbpData = await _loadMortgageData(prefs, 'uk_mortgage');

      final payload = {
        'eur_data': eurData,
        'gbp_data': gbpData,
        'conversion_rate': double.tryParse(_conversionRateC.text) ?? 0.85
      };

      final savedPath = await exportAndSaveRolloverExcel(_pythonPlugin, payload);

      setState(() {
        _errorText = "Export finished";
      });

      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text('Rollover Excel exported'),
            content: Text('Saved to:\n$savedPath'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await OpenFile.open(savedPath);
                },
                child: const Text('Open file'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await Share.shareXFiles([XFile(savedPath)], text: 'Rollover analysis exported');
                },
                child: const Text('Share'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      setState(() {
        _errorText = "Export failed: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _processRolloverResponse(String responseString) {
    try {
      final resultMap = json.decode(responseString) as Map<String, dynamic>;

      if (resultMap.containsKey('error')) {
        setState(() {
          String dataReceived = "";
          if (resultMap.containsKey('received_data') && resultMap['received_data'] is Map) {
            dataReceived = jsonEncode(resultMap['received_data']);
          } else if (resultMap.containsKey('received_data')) {
            dataReceived = resultMap['received_data'].toString();
          }

          _errorText = "Python Error: ${resultMap['error']}\nData Sent: $dataReceived";
        });
        return;
      }

      setState(() {
        _eurPayoffTime = "${resultMap['eur_payoff_time_years']} years (${resultMap['eur_payoff_time_months']} months)";
        _eurFreedPayment = "€${resultMap['eur_freed_payment']} ≈ £${resultMap['gbp_freed_payment']} (rate ${resultMap['conversion_rate']})";
        _eurBaselineInterest = "€${resultMap['eur_baseline_interest']}";
        _eurOverpayInterest = "€${resultMap['eur_overpay_interest']}";
        _eurInterestSaved = "€${resultMap['eur_interest_saved']}";

        _ukBaselinePayoff = "${resultMap['uk_baseline_payoff_years']} years";
        _ukRemainingTerm = "${resultMap['uk_remaining_term_at_payoff_years']} years (${resultMap['uk_remaining_term_at_payoff_months']} months)";
        _ukBaselineInterest = "£${resultMap['uk_baseline_total_interest']}";

        _ukBalanceAtRollover = "£${resultMap['uk_balance_at_rollover']}";
        _ukExtraMonthly = "£${resultMap['uk_extra_monthly_from_eur']}";
        _ukAnnualPct = "${resultMap['uk_annual_overpay_pct']}% of balance (cap ~10%)";
        _ukPayoffAfterRollover = "${resultMap['uk_payoff_after_rollover_years']} years";
        _ukTotalInterestRollover = "£${resultMap['uk_total_interest_with_rollover']}";
        _ukInterestSaved = "£${resultMap['uk_interest_saved_vs_baseline']}";

        _compBaseline = "${resultMap['comparison_baseline_years']}";
        _compWithRollover = "${resultMap['comparison_with_rollover_years']}";
        _compTimeSaved = "${resultMap['comparison_time_saved_years']}";

        _totalMortgageFreeTime = "${resultMap['total_mortgage_free_time_years']} years 🇬🇧 🎉";
      });
    } catch (e) {
      setState(() {
        _errorText = "Failed to parse Python response: ${e.toString()} \nRaw: $responseString";
      });
    }
  }

  void _clearResults() {
    _eurPayoffTime = "...";
    _eurFreedPayment = "...";
    _eurBaselineInterest = "...";
    _eurOverpayInterest = "...";
    _eurInterestSaved = "...";
    _ukBaselinePayoff = "...";
    _ukRemainingTerm = "...";
    _ukBaselineInterest = "...";
    _ukBalanceAtRollover = "...";
    _ukExtraMonthly = "...";
    _ukAnnualPct = "...";
    _ukPayoffAfterRollover = "...";
    _ukTotalInterestRollover = "...";
    _ukInterestSaved = "...";
    _compBaseline = "...";
    _compWithRollover = "...";
    _compTimeSaved = "...";
    _totalMortgageFreeTime = "...";
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "EUR → UK Rollover Simulation",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)
          ),
          const Text(
            "This tool reads your saved EUR and UK mortgage data and simulates paying off the EUR loan, then 'rolling' its monthly payment onto the UK loan.",
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const Divider(height: 24),
          TextField(
            controller: _conversionRateC,
            decoration: const InputDecoration(
              labelText: "EUR→GBP Conversion Rate",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.currency_exchange),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.compare_arrows),
            label: Text(_isLoading ? "Simulating..." : "Run Rollover Comparison"),
            onPressed: _isLoading ? null : _runRolloverSimulation,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.file_download),
            label: const Text('Export rollover Excel'),
            onPressed: _isLoading ? null : _exportRolloverExcel,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          if (_errorText.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.red[100],
              child: Text(_errorText, style: const TextStyle(color: Colors.black87)),
            ),
          if (_errorText.isEmpty) ...[
            _ResultCard(
              title: "EUR Mortgage",
              children: [
                _ResultRow("Payoff time:", _eurPayoffTime),
                _ResultRow("Freed monthly payment:", _eurFreedPayment),
                _ResultRow("Baseline total interest:", _eurBaselineInterest),
                _ResultRow("With overpay total interest:", _eurOverpayInterest),
                _ResultRow("💡 Interest saved vs baseline:", _eurInterestSaved, isSaved: true),
              ],
            ),
            _ResultCard(
              title: "UK Mortgage — Baseline",
              children: [
                _ResultRow("Payoff time without rollover:", _ukBaselinePayoff),
                _ResultRow("Remaining UK term at EUR payoff:", _ukRemainingTerm),
                _ResultRow("Baseline total interest:", _ukBaselineInterest),
              ],
            ),
            _ResultCard(
              title: "UK Mortgage — With EUR Rollover",
              children: [
                _ResultRow("UK balance at rollover:", _ukBalanceAtRollover),
                _ResultRow("Extra monthly from EUR payoff:", _ukExtraMonthly),
                _ResultRow("Annual overpayment ≈", _ukAnnualPct),
                _ResultRow("UK payoff after rollover:", _ukPayoffAfterRollover),
                _ResultRow("Total interest (with rollover):", _ukTotalInterestRollover),
                _ResultRow("💡 Interest saved vs baseline:", _ukInterestSaved, isSaved: true),
              ],
            ),
            _ResultCard(
              title: "Comparison (UK)",
              isComparison: true,
              children: [
                _ComparisonTable(
                  baseline: _compBaseline,
                  withRollover: _compWithRollover,
                  timeSaved: _compTimeSaved,
                ),
                const SizedBox(height: 16),
                _ResultRow("Total mortgage-free time:", _totalMortgageFreeTime, isTotal: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isComparison;

  const _ResultCard({ Key? key, required this.title, required this.children, this.isComparison = false }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isComparison ? Colors.blueAccent : Colors.grey[300]!, width: isComparison ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(height: 16),
          ...children,
        ]),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isSaved;
  final bool isTotal;

  const _ResultRow(this.label, this.value, { Key? key, this.isSaved = false, this.isTotal = false }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final valueStyle = style?.copyWith(fontWeight: FontWeight.bold, color: isSaved ? Colors.green[700] : (isTotal ? Colors.blue[800] : null));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 8),
        value.isEmpty || value == "..."
            ? const SizedBox(height: 10, width: 10, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(value, style: valueStyle, textAlign: TextAlign.right),
      ]),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  final String baseline;
  final String withRollover;
  final String timeSaved;

  const _ComparisonTable({ Key? key, required this.baseline, required this.withRollover, required this.timeSaved }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(color: Colors.grey[300]!, borderRadius: BorderRadius.circular(4)),
      children: [
        _buildTableRow(context, "Scenario", "Payoff Time (yrs)", isHeader: true),
        _buildTableRow(context, "Baseline (no rollover)", baseline),
        _buildTableRow(context, "With EUR rollover", withRollover),
        _buildTableRow(context, "Time saved after rollover", timeSaved, isBold: true),
      ],
    );
  }

  TableRow _buildTableRow(BuildContext context, String col1, String col2, { bool isHeader = false, bool isBold = false }) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal);
    return TableRow(children: [
      Padding(padding: const EdgeInsets.all(8.0), child: Text(col1, style: style)),
      Padding(padding: const EdgeInsets.all(8.0), child: Text(col2, style: style, textAlign: TextAlign.right)),
    ]);
  }
}