// lib/services/savings_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

var _uuid = const Uuid();

// 1. The Data Model for a single platform
class SavingsPlatform {
  String id;
  String name;
  double balance;
  String currency; // "EUR" or "GBP"

  SavingsPlatform({
    required this.id,
    required this.name,
    this.balance = 0.0,
    this.currency = "GBP",
  });

  // Convert to/from JSON to save to storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'balance': balance,
    'currency': currency,
  };

  factory SavingsPlatform.fromJson(Map<String, dynamic> json) {
    return SavingsPlatform(
      id: json['id'],
      name: json['name'],
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'GBP',
    );
  }
}

// 2. The Service to manage saving & loading
class SavingsService {
  static const _storageKey = 'savings_platforms_list';

  // Load all platforms from phone storage
  Future<List<SavingsPlatform>> loadPlatforms() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_storageKey);

    if (jsonString == null) {
      return []; // Return an empty list if nothing is saved
    }

    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => SavingsPlatform.fromJson(json)).toList();
  }

  // Save the entire list of platforms to phone storage
  Future<void> savePlatforms(List<SavingsPlatform> platforms) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> jsonList = platforms.map((p) => p.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }
  
  // Helper to create a new, empty platform
  SavingsPlatform createNewPlatform(String name, String currency) {
    return SavingsPlatform(
      id: _uuid.v4(),
      name: name,
      currency: currency,
    );
  }
}