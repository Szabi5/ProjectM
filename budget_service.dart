// lib/services/budget_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

var _uuid = const Uuid();

enum BudgetItemType { Income, Expense }
enum BudgetFrequency { Weekly, Monthly, Quarterly, Yearly }

// --- UPDATED CATEGORY MODEL ---
class Category {
  final String id;
  String name;
  String colorHex; 
  BudgetItemType type; 
  bool isVariable; // <--- NEW: Marks category for Quick Add (e.g. Groceries)

  Category({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.type,
    this.isVariable = false, // Default is fixed
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorHex': colorHex,
    'type': type.toString(),
    'isVariable': isVariable, // <--- NEW
  };

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
      colorHex: json['colorHex'] ?? '#FFD32F2F',
      type: BudgetItemType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => BudgetItemType.Expense,
      ),
      isVariable: json['isVariable'] ?? false, // <--- NEW
    );
  }
}

class BudgetItem {
  String id;
  String name;
  double amount;
  String currency; 
  BudgetItemType type;
  BudgetFrequency frequency;
  String categoryId; 

  BudgetItem({
    required this.id,
    required this.name,
    this.amount = 0.0,
    this.currency = "GBP",
    this.type = BudgetItemType.Expense,
    this.frequency = BudgetFrequency.Monthly,
    this.categoryId = 'default-uncategorized', 
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'currency': currency,
    'type': type.toString(),
    'frequency': frequency.toString(),
    'categoryId': categoryId,
  };

  factory BudgetItem.fromJson(Map<String, dynamic> json) {
    return BudgetItem(
      id: json['id'],
      name: json['name'],
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'GBP',
      type: BudgetItemType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => BudgetItemType.Expense,
      ),
      frequency: BudgetFrequency.values.firstWhere(
        (e) => e.toString() == json['frequency'],
        orElse: () => BudgetFrequency.Monthly,
      ),
      categoryId: json['categoryId'] ?? 'default-uncategorized', 
    );
  }
}

class BudgetService {
  static const _storageKey = 'budget_items_list';
  static const _categoryStorageKey = 'budget_categories_list';

  Future<List<Category>> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_categoryStorageKey);
    
    if (jsonString == null) {
      // DEFAULT CATEGORIES (Updated with examples)
      return [
        Category(id: 'default-uncategorized', name: 'Uncategorized', colorHex: '#FF757575', type: BudgetItemType.Expense),
        Category(id: 'default-savings', name: 'Savings', colorHex: '#FF4CAF50', type: BudgetItemType.Expense),
        Category(id: 'default-housing', name: 'Housing', colorHex: '#FF03A9F4', type: BudgetItemType.Expense),
        Category(id: 'default-salary', name: 'Salary', colorHex: '#FF4CAF50', type: BudgetItemType.Income),
        // New default variable category
        Category(id: 'default-living', name: 'Daily Living', colorHex: '#FF9C27B0', type: BudgetItemType.Expense, isVariable: true), 
      ]; 
    }

    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => Category.fromJson(json)).toList();
  }
  
  Future<void> saveCategories(List<Category> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> jsonList = categories.map((c) => c.toJson()).toList();
    await prefs.setString(_categoryStorageKey, jsonEncode(jsonList));
  }
  
  Future<List<BudgetItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_storageKey);

    if (jsonString == null) {
      return []; 
    }

    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => BudgetItem.fromJson(json)).toList();
  }

  Future<void> saveItems(List<BudgetItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> jsonList = items.map((i) => i.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }
  
  BudgetItem createNewItem(String name, String currency, BudgetItemType type, BudgetFrequency frequency, {String categoryId = 'default-uncategorized'}) {
    return BudgetItem(
      id: _uuid.v4(),
      name: name,
      currency: currency,
      type: type,
      frequency: frequency,
      categoryId: categoryId, 
    );
  }
}