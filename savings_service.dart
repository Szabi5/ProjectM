// lib/services/savings_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

var _uuid = const Uuid();

// --- NEW: Data Model for Savings Category ---
class SavingsCategory {
  final String id;
  String name;
  String colorHex;

  SavingsCategory({
    required this.id,
    required this.name,
    required this.colorHex,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorHex': colorHex,
  };

  factory SavingsCategory.fromJson(Map<String, dynamic> json) {
    return SavingsCategory(
      id: json['id'],
      name: json['name'],
      colorHex: json['colorHex'] ?? '#FF4CAF50', // Default Green
    );
  }
}

// 1. Updated Data Model for a single platform
class SavingsPlatform {
  String id;
  String name;
  double balance;
  String currency; // "EUR" or "GBP"
  String categoryId; // <--- NEW FIELD

  SavingsPlatform({
    required this.id,
    required this.name,
    this.balance = 0.0,
    this.currency = "GBP",
    this.categoryId = 'default-savings-uncategorized', // Default for migration
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'balance': balance,
    'currency': currency,
    'categoryId': categoryId,
  };

  factory SavingsPlatform.fromJson(Map<String, dynamic> json) {
    return SavingsPlatform(
      id: json['id'],
      name: json['name'],
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'GBP',
      categoryId: json['categoryId'] ?? 'default-savings-uncategorized',
    );
  }
}

// 2. Service to manage saving & loading
class SavingsService {
  static const _storageKey = 'savings_platforms_list';
  static const _categoryStorageKey = 'savings_categories_list';

  // --- Category Management ---

  Future<List<SavingsCategory>> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_categoryStorageKey);
    
    if (jsonString == null) {
      // Default Savings Categories
      return [
        SavingsCategory(id: 'default-savings-uncategorized', name: 'General Savings', colorHex: '#FF9E9E9E'), // Grey
        SavingsCategory(id: 'default-investments', name: 'Investments (ISA/GIA)', colorHex: '#FF2196F3'), // Blue
        SavingsCategory(id: 'default-pension', name: 'Pensions', colorHex: '#FF673AB7'), // Purple
        SavingsCategory(id: 'default-crypto', name: 'Crypto', colorHex: '#FFFFC107'), // Amber
      ]; 
    }

    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => SavingsCategory.fromJson(json)).toList();
  }
  
  Future<void> saveCategories(List<SavingsCategory> categories) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> jsonList = categories.map((c) => c.toJson()).toList();
    await prefs.setString(_categoryStorageKey, jsonEncode(jsonList));
  }

  // --- Platform Management ---

  Future<List<SavingsPlatform>> loadPlatforms() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_storageKey);

    if (jsonString == null) {
      return []; 
    }

    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => SavingsPlatform.fromJson(json)).toList();
  }

  Future<void> savePlatforms(List<SavingsPlatform> platforms) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> jsonList = platforms.map((p) => p.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }
  
  SavingsPlatform createNewPlatform(String name, String currency, String categoryId) {
    return SavingsPlatform(
      id: _uuid.v4(),
      name: name,
      currency: currency,
      categoryId: categoryId,
    );
  }
}