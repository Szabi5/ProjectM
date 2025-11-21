// lib/services/budget_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

var _uuid = const Uuid();

// --- Enums for type-safety ---
enum BudgetItemType { Income, Expense }
enum BudgetFrequency { Weekly, Monthly }

// 1. The Data Model for a single budget item
class BudgetItem {
  String id;
  String name;
  double amount;
  String currency; // "EUR" or "GBP"
  BudgetItemType type;
  BudgetFrequency frequency;

  BudgetItem({
    required this.id,
    required this.name,
    this.amount = 0.0,
    this.currency = "GBP",
    this.type = BudgetItemType.Expense,
    this.frequency = BudgetFrequency.Monthly,
  });

  // Convert to/from JSON to save to storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'currency': currency,
    'type': type.toString(), // Save enum as string
    'frequency': frequency.toString(), // Save enum as string
  };

  factory BudgetItem.fromJson(Map<String, dynamic> json) {
    return BudgetItem(
      id: json['id'],
      name: json['name'],
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'GBP',
      // Load enum from string, with a default
      type: BudgetItemType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => BudgetItemType.Expense,
      ),
      frequency: BudgetFrequency.values.firstWhere(
        (e) => e.toString() == json['frequency'],
        orElse: () => BudgetFrequency.Monthly,
      ),
    );
  }
}

// 2. The Service to manage saving & loading
class BudgetService {
  static const _storageKey = 'budget_items_list';

  // Load all items from phone storage
  Future<List<BudgetItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_storageKey);

    if (jsonString == null) {
      return []; // Return an empty list if nothing is saved
    }

    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => BudgetItem.fromJson(json)).toList();
  }

  // Save the entire list of items to phone storage
  Future<void> saveItems(List<BudgetItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> jsonList = items.map((i) => i.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }
  
  // Helper to create a new, empty item
  BudgetItem createNewItem(String name, String currency, BudgetItemType type, BudgetFrequency frequency) {
    return BudgetItem(
      id: _uuid.v4(),
      name: name,
      currency: currency,
      type: type,
      frequency: frequency,
    );
  }
}