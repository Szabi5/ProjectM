import 'package:flutter/material.dart';
import '../services/ai_summary_service.dart';

class AiSummaryScreen extends StatelessWidget {
  final AiSummary summary;

  const AiSummaryScreen({
    super.key,
    required this.summary,
  });

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(body,
                  style: const TextStyle(fontSize: 15, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Financial Summary"),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _section("Overview", summary.overview),
            _section("Savings Insight", summary.savingsInsight),
            _section("Budget Insight", summary.budgetInsight),
            _section("Debt Insight", summary.debtInsight),
            _section("Net Worth Insight", summary.netWorthInsight),
            _section("Suggested Actions", summary.actions),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
