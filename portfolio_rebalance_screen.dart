// lib/screens/portfolio_rebalance_screen.dart
//
// Responsive fixes for the filter row to avoid overflow on narrow devices.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/portfolio_service.dart';
import '../services/ai_service.dart';
import '../models/investment_holding.dart';
import 'dart:math';

class PortfolioRebalanceScreen extends StatefulWidget {
  const PortfolioRebalanceScreen({Key? key}) : super(key: key);

  @override
  State<PortfolioRebalanceScreen> createState() => _PortfolioRebalanceScreenState();
}

class _PortfolioRebalanceScreenState extends State<PortfolioRebalanceScreen> {
  final _service = PortfolioService();
  final _aiService = AIService();

  List<InvestmentHolding> _allHoldings = [];
  List<InvestmentHolding> _displayedHoldings = [];

  Map<String, String> _suggestions = {};
  bool _isLoading = false;
  bool _isAiAnalyzing = false;
  double _totalValue = 0.0;

  String? _selectedFile;
  List<String> _availableFiles = [];
  String _strategy = "Growth & Aggressive";

  // --- Helper to safely get ticker label ---
  String _getTickerLabel(String ticker) {
    if (ticker.isEmpty) return "?";
    if (ticker.length > 3) return ticker.substring(0, 3);
    return ticker;
  }

  void _importFiles() async {
    setState(() => _isLoading = true);
    final data = await _service.importInvestments();
    if (data.isNotEmpty) {
      setState(() {
        _allHoldings.addAll(data);
        _updateFilterOptions();
        _applyFilter();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Imported ${data.length} positions.")));
    }
    setState(() => _isLoading = false);
  }

  void _clearPortfolio() {
    setState(() {
      _allHoldings = [];
      _displayedHoldings = [];
      _availableFiles = [];
      _selectedFile = null;
      _suggestions = {};
      _totalValue = 0.0;
    });
  }

  void _updateFilterOptions() {
    final sources = _allHoldings.map((h) => h.sourceFile).toSet().toList();
    sources.sort();
    _availableFiles = sources;
  }

  void _applyFilter() {
    if (_selectedFile == null) {
      _displayedHoldings = List.from(_allHoldings);
    } else {
      _displayedHoldings = _allHoldings.where((h) => h.sourceFile == _selectedFile).toList();
    }
    _calculateTotals();
    _suggestions = _service.generateSuggestions(_displayedHoldings);
  }

  void _calculateTotals() {
    _totalValue = _displayedHoldings.fold(0, (sum, h) => sum + h.currentValue);
  }

  void _runLiveAnalysis() async {
    if (_allHoldings.isEmpty) return;
    setState(() => _isLoading = true);

    final updatedAll = await _service.fetchLiveMarketUpdates(_allHoldings);

    setState(() {
      _allHoldings = updatedAll;
      _applyFilter();
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Live Market Analysis Complete 📊")));
  }

  void _askAiAnalyst() async {
    if (_displayedHoldings.isEmpty) return;
    setState(() => _isAiAnalyzing = true);

    final report = await _aiService.analyzePortfolio(_displayedHoldings, _strategy);

    setState(() => _isAiAnalyzing = false);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("🤖 AI Analyst Report", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: Markdown(
                data: report,
                padding: const EdgeInsets.all(16),
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: const TextStyle(fontSize: 16),
                  h1: const TextStyle(color: Colors.amber, fontSize: 22, fontWeight: FontWeight.bold),
                  strong: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Portfolio AI"),
        actions: [
          if (_allHoldings.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _clearPortfolio,
              tooltip: "Clear Portfolio",
            ),
          IconButton(
              icon: const Icon(Icons.file_upload), onPressed: _importFiles, tooltip: "Import CSVs"),
        ],
      ),
      body: _allHoldings.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                // --- Filter & Strategy Row (RESPONSIVE) ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: LayoutBuilder(builder: (context, constraints) {
                    // Switch to stacked column on narrow widths to avoid overflow
                    final isNarrow = constraints.maxWidth < 480;
                    if (isNarrow) {
                      // stacked layout
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_availableFiles.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: DropdownButtonFormField<String?>(
                                value: _selectedFile,
                                isExpanded: true,
                                isDense: true,
                                decoration: const InputDecoration(
                                  labelText: "Portfolio",
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                ),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text("All")),
                                  ..._availableFiles.map((file) => DropdownMenuItem(value: file, child: Text(file, overflow: TextOverflow.ellipsis)))
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedFile = val;
                                    _applyFilter();
                                  });
                                },
                              ),
                            ),
                          DropdownButtonFormField<String>(
                            value: _strategy,
                            isExpanded: true,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: "Target Strategy",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            ),
                            items: const [
                              DropdownMenuItem(value: "Growth & Aggressive", child: Text("Growth 🚀")),
                              DropdownMenuItem(value: "Dividend & Income", child: Text("Income 💰")),
                              DropdownMenuItem(value: "Balanced & Safe", child: Text("Balanced ⚖️")),
                            ],
                            onChanged: (val) => setState(() => _strategy = val!),
                          ),
                        ],
                      );
                    } else {
                      // side-by-side layout for wider screens
                      return Row(
                        children: [
                          if (_availableFiles.isNotEmpty)
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                value: _selectedFile,
                                isExpanded: true,
                                isDense: true,
                                decoration: const InputDecoration(
                                  labelText: "Portfolio",
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                ),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text("All")),
                                  ..._availableFiles.map((file) => DropdownMenuItem(value: file, child: Text(file, overflow: TextOverflow.ellipsis)))
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedFile = val;
                                    _applyFilter();
                                  });
                                },
                              ),
                            ),
                          if (_availableFiles.isNotEmpty) const SizedBox(width: 10) else const SizedBox(width: 0),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _strategy,
                              isExpanded: true,
                              isDense: true,
                              decoration: const InputDecoration(
                                labelText: "Target Strategy",
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              ),
                              items: const [
                                DropdownMenuItem(value: "Growth & Aggressive", child: Text("Growth 🚀")),
                                DropdownMenuItem(value: "Dividend & Income", child: Text("Income 💰")),
                                DropdownMenuItem(value: "Balanced & Safe", child: Text("Balanced ⚖️")),
                              ],
                              onChanged: (val) => setState(() => _strategy = val!),
                            ),
                          ),
                        ],
                      );
                    }
                  }),
                ),

                // --- Header Card ---
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  color: Colors.blueGrey.shade900,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_selectedFile ?? "Total Wealth", style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(currency.format(_totalValue), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _isLoading ? null : _runLiveAnalysis,
                              icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, color: Colors.greenAccent),
                              tooltip: "Refresh Prices",
                            )
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isAiAnalyzing ? null : _askAiAnalyst,
                            icon: _isAiAnalyzing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                : const Icon(Icons.psychology),
                            label: Text(_isAiAnalyzing ? "AI is thinking..." : "Ask AI Analyst"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigoAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // --- Holdings List (FIXED: Replaced ListTile with Custom Row) ---
                Expanded(
                  child: ListView.builder(
                    itemCount: _displayedHoldings.length,
                    itemBuilder: (context, index) {
                      final item = _displayedHoldings[index];
                      final suggestion = _suggestions[item.ticker];
                      final isProfit = item.profitLoss >= 0;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Padding(
                          // Custom Padding to ensure content fits comfortably
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          child: Row(
                            children: [
                              // 1. Avatar
                              CircleAvatar(
                                backgroundColor: isProfit ? Colors.green.shade900 : Colors.red.shade900,
                                child: Text(_getTickerLabel(item.ticker), style: const TextStyle(fontSize: 10, color: Colors.white)),
                              ),
                              const SizedBox(width: 16),

                              // 2. Main Info (Takes available space)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text(item.sourceFile, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // 3. Trailing Info (Aligned End)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(currency.format(item.currentValue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  if (suggestion != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(suggestion,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: suggestion.startsWith("🔴") ? Colors.red : (suggestion.startsWith("🟢") ? Colors.green : Colors.grey))),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.pie_chart_outline, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text("No Portfolio Data", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Upload your Trading212 CSVs to get started.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _importFiles,
            icon: const Icon(Icons.upload_file),
            label: const Text("Upload CSV Files"),
          )
        ],
      ),
    );
  }
}