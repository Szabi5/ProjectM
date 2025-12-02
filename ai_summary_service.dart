// lib/services/ai_summary_service.dart
//
// Clean, safe, real AI-style text generator
// Works WITHOUT GPT, but structured so GPT can be added later easily.

import 'package:intl/intl.dart';
import '../services/history_service.dart';
import '../services/budget_service.dart';
import '../services/savings_service.dart';

class AiSummary {
  final String overview;
  final String savingsInsight;
  final String budgetInsight;
  final String debtInsight;
  final String netWorthInsight;
  final String actions;

  AiSummary({
    required this.overview,
    required this.savingsInsight,
    required this.budgetInsight,
    required this.debtInsight,
    required this.netWorthInsight,
    required this.actions,
  });
}

class AiSummaryService {
  final NumberFormat gbp = NumberFormat.currency(
      locale: 'en_GB', symbol: '£', decimalDigits: 0
  );

  Future<AiSummary> generateFromSnapshot({
    required double netWorth,
    required double totalAssets,
    required double totalLiabilities,
    required double totalMonthlyIncome,
    required double totalMonthlyExpenses,
    required double monthlySurplus,
    required double euAssets,
    required double ukAssets,
    required double euLiabilities,
    required double ukLiabilities,
    required List<SavingsPlatform> platforms,
    required List<BudgetItem> budgetItems,
    required HistoryService historyService,
  }) async {
    // ---- 1. Load HISTORY TREND ----
    final List<FinancialSnapshot> history =
        await historyService.loadAllSnapshots(); // Already exists

    double? lastMonthNetWorth;
    double? changeAmount;
    double? changePercent;

    if (history.length >= 2) {
      final sorted = [...history]..sort((a, b) => a.savedDate.compareTo(b.savedDate));
      lastMonthNetWorth = sorted[sorted.length - 2].netWorth;

      changeAmount = netWorth - lastMonthNetWorth;
      if (lastMonthNetWorth != 0) {
        changePercent = (changeAmount / lastMonthNetWorth) * 100;
      }
    }

    // ---- SUMMARY TEXTS ----

    // 1. Overview
    final overview = _buildOverview(
      netWorth: netWorth,
      changeAmount: changeAmount,
      changePercent: changePercent,
    );

    // 2. Savings Insight
    final savingsInsight = _buildSavingsInsight(
      platforms: platforms,
      euAssets: euAssets,
      ukAssets: ukAssets,
    );

    // 3. Budget Insight
    final budgetInsight = _buildBudgetInsight(
      income: totalMonthlyIncome,
      expenses: totalMonthlyExpenses,
      surplus: monthlySurplus,
    );

    // 4. Debt Insight
    final debtInsight = _buildDebtInsight(
      euLiabilities: euLiabilities,
      ukLiabilities: ukLiabilities,
      totalLiabilities: totalLiabilities,
    );

    // 5. Net Worth Insight
    final netWorthInsight = _buildNetWorthInsight(
      netWorth: netWorth,
      assets: totalAssets,
      liabilities: totalLiabilities,
    );

    // 6. Action Plan
    final actions = _buildActions(
      surplus: monthlySurplus,
      liabilities: totalLiabilities,
      savingsGbps: platforms.where((p) => p.currency != "EUR").fold(0.0, (sum, p) => sum + p.balance),
    );

    return AiSummary(
      overview: overview,
      savingsInsight: savingsInsight,
      budgetInsight: budgetInsight,
      debtInsight: debtInsight,
      netWorthInsight: netWorthInsight,
      actions: actions,
    );
  }

  // ----------------------------------------------
  // ------------ SUMMARY BUILDING ---------------
  // ----------------------------------------------

  String _buildOverview({
    required double netWorth,
    double? changeAmount,
    double? changePercent,
  }) {
    String base = "Your current net worth is ${gbp.format(netWorth)}.";

    if (changeAmount == null) {
      return "$base This is your first recorded snapshot, so trend data will appear next month.";
    }

    final changeText = changeAmount >= 0
        ? "increased by ${gbp.format(changeAmount)}"
        : "decreased by ${gbp.format(changeAmount.abs())}";

    final percent = changePercent != null
        ? " (${changePercent.toStringAsFixed(1)}%)"
        : "";

    return "$base It has $changeText$percent compared to last month.";
  }

  String _buildSavingsInsight({
    required List<SavingsPlatform> platforms,
    required double euAssets,
    required double ukAssets,
  }) {
    final totalSavings = platforms.fold(0.0, (sum, p) => sum + p.balance);
    final eurPart = platforms.where((p) => p.currency == "EUR").fold(0.0, (sum, p) => sum + p.balance);

    return "You currently hold ${gbp.format(totalSavings)} in savings and investments. "
        "A portion of this (${eurPart.toStringAsFixed(0)}€) is held in EUR-based accounts. "
        "Your assets are split between EU (${eurPart.toStringAsFixed(0)}€) and UK holdings "
        "(${gbp.format(ukAssets)}). Asset diversification between currencies provides stability "
        "but exposes you to FX fluctuation risk.";
  }

  String _buildBudgetInsight({
    required double income,
    required double expenses,
    required double surplus,
  }) {
    return "Your monthly income is ${gbp.format(income)}, while expenses total ${gbp.format(expenses)}. "
        "This leaves you with a monthly surplus of ${gbp.format(surplus)}. "
        "A positive surplus is ideal, but if expenses rise or income drops, your budget could tighten.";
  }

  String _buildDebtInsight({
    required double euLiabilities,
    required double ukLiabilities,
    required double totalLiabilities,
  }) {
    return "You currently owe ${gbp.format(totalLiabilities)} across all liabilities, including "
        "${gbp.format(ukLiabilities)} in UK debt and ${gbp.format(euLiabilities)} (converted) in EU debt. "
        "Monitoring interest rates in both regions will help optimize long-term payoff.";
  }

  String _buildNetWorthInsight({
    required double netWorth,
    required double assets,
    required double liabilities,
  }) {
    return "Your total assets are valued at ${gbp.format(assets)}, with liabilities at ${gbp.format(liabilities)}. "
        "This results in a net worth of ${gbp.format(netWorth)}. Maintaining strong savings growth while reducing "
        "liabilities will steadily increase your long-term wealth.";
  }

  String _buildActions({
    required double surplus,
    required double liabilities,
    required double savingsGbps,
  }) {
    List<String> items = [];

    if (surplus > 300) {
      items.add("Increase monthly investments or savings contributions.");
    } else if (surplus > 0) {
      items.add("Your budget is healthy. Consider optimising expenses to increase surplus.");
    } else {
      items.add("Monthly deficit detected — review discretionary spending.");
    }

    if (liabilities > savingsGbps * 2) {
      items.add("Your liabilities are high relative to liquid savings; prioritise debt reduction.");
    }

    items.add("Review your FX exposure between GBP and EUR assets.");

    return "Recommended actions:\n• ${items.join("\n• ")}";
  }
}
