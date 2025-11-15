// lib/services/history_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // For formatting the month key

// 1. The Data Model for a single monthly snapshot
class FinancialSnapshot {
  final String yearMonth; // "YYYY-MM" format, e.g., "2025-11"
  final DateTime savedDate;
  
  // High-Level Totals
  final double netWorth;
  final double totalAssetsGbp;
  final double totalLiabilitiesGbp;
  
  // Asset Breakdown (GBP)
  final double euAssetsGbp;
  final double ukAssetsGbp;
  final double euAssetsEur; // Original currency
  
  // Liability Breakdown (GBP)
  final double euLiabilitiesGbp;
  final double ukLiabilitiesGbp;
  final double euLiabilitiesEur; // Original currency
  
  // Raw Balances (Original Currencies)
  final double euMortgageBalance;
  final double ukMortgageBalance;
  final double creditCardBalance;
  final double euSavings;
  final double gbpSavings;

  // Cash Flow (GBP)
  final double monthlyIncome;
  final double monthlyExpenses;
  final double monthlySurplus;

  FinancialSnapshot({
    required this.yearMonth,
    required this.savedDate,
    required this.netWorth,
    required this.totalAssetsGbp,
    required this.totalLiabilitiesGbp,
    required this.euAssetsGbp,
    required this.ukAssetsGbp,
    required this.euAssetsEur,
    required this.euLiabilitiesGbp,
    required this.ukLiabilitiesGbp,
    required this.euLiabilitiesEur,
    required this.euMortgageBalance,
    required this.ukMortgageBalance,
    required this.creditCardBalance,
    required this.euSavings,
    required this.gbpSavings,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.monthlySurplus,
  });

  // Convert to/from JSON to save to storage
  Map<String, dynamic> toJson() => {
    'yearMonth': yearMonth,
    'savedDate': savedDate.toIso8601String(),
    'netWorth': netWorth,
    'totalAssetsGbp': totalAssetsGbp,
    'totalLiabilitiesGbp': totalLiabilitiesGbp,
    'euAssetsGbp': euAssetsGbp,
    'ukAssetsGbp': ukAssetsGbp,
    'euAssetsEur': euAssetsEur,
    'euLiabilitiesGbp': euLiabilitiesGbp,
    'ukLiabilitiesGbp': ukLiabilitiesGbp,
    'euLiabilitiesEur': euLiabilitiesEur,
    'euMortgageBalance': euMortgageBalance,
    'ukMortgageBalance': ukMortgageBalance,
    'creditCardBalance': creditCardBalance,
    'euSavings': euSavings,
    'gbpSavings': gbpSavings,
    'monthlyIncome': monthlyIncome,
    'monthlyExpenses': monthlyExpenses,
    'monthlySurplus': monthlySurplus,
  };

  factory FinancialSnapshot.fromJson(Map<String, dynamic> json) {
    return FinancialSnapshot(
      yearMonth: json['yearMonth'],
      savedDate: DateTime.parse(json['savedDate']),
      netWorth: (json['netWorth'] as num?)?.toDouble() ?? 0.0,
      totalAssetsGbp: (json['totalAssetsGbp'] as num?)?.toDouble() ?? 0.0,
      totalLiabilitiesGbp: (json['totalLiabilitiesGbp'] as num?)?.toDouble() ?? 0.0,
      euAssetsGbp: (json['euAssetsGbp'] as num?)?.toDouble() ?? 0.0,
      ukAssetsGbp: (json['ukAssetsGbp'] as num?)?.toDouble() ?? 0.0,
      euAssetsEur: (json['euAssetsEur'] as num?)?.toDouble() ?? 0.0,
      euLiabilitiesGbp: (json['euLiabilitiesGbp'] as num?)?.toDouble() ?? 0.0,
      ukLiabilitiesGbp: (json['ukLiabilitiesGbp'] as num?)?.toDouble() ?? 0.0,
      euLiabilitiesEur: (json['euLiabilitiesEur'] as num?)?.toDouble() ?? 0.0,
      euMortgageBalance: (json['euMortgageBalance'] as num?)?.toDouble() ?? 0.0,
      ukMortgageBalance: (json['ukMortgageBalance'] as num?)?.toDouble() ?? 0.0,
      creditCardBalance: (json['creditCardBalance'] as num?)?.toDouble() ?? 0.0,
      euSavings: (json['euSavings'] as num?)?.toDouble() ?? 0.0,
      gbpSavings: (json['gbpSavings'] as num?)?.toDouble() ?? 0.0,
      monthlyIncome: (json['monthlyIncome'] as num?)?.toDouble() ?? 0.0,
      monthlyExpenses: (json['monthlyExpenses'] as num?)?.toDouble() ?? 0.0,
      monthlySurplus: (json['monthlySurplus'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// 2. The Service to manage saving & loading
class HistoryService {
  static const _storageKey = 'financial_history_snapshots';

  // Load all snapshots from phone storage, sorted newest first
  Future<List<FinancialSnapshot>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_storageKey);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = jsonDecode(jsonString);
    List<FinancialSnapshot> snapshots = jsonList.map((json) => FinancialSnapshot.fromJson(json)).toList();
    
    // Sort by date, newest first
    snapshots.sort((a, b) => b.savedDate.compareTo(a.savedDate));
    return snapshots;
  }

  // Saves a new snapshot. Overwrites any existing snapshot for the same month.
  Future<void> saveSnapshot(FinancialSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    List<FinancialSnapshot> history = await loadHistory();

    // Remove any existing snapshot for this month
    history.removeWhere((s) => s.yearMonth == snapshot.yearMonth);
    
    // Add the new one
    history.add(snapshot);

    // Save the updated list
    final List<Map<String, dynamic>> jsonList = history.map((s) => s.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }
}