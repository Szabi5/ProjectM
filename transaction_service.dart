// lib/services/transaction_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_item.dart';

class TransactionService {
  static const _storageKey = 'recent_transactions_list';

  Future<List<TransactionItem>> loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_storageKey);

    if (jsonString == null) return [];

    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => TransactionItem.fromJson(json)).toList();
  }

  Future<void> saveTransaction(TransactionItem item) async {
    final prefs = await SharedPreferences.getInstance();
    List<TransactionItem> transactions = await loadTransactions();
    
    // Add new transaction to the start of the list
    transactions.insert(0, item);
    
    // Optional: Limit history to last 100 items to save space
    if (transactions.length > 100) {
      transactions = transactions.sublist(0, 100);
    }

    final List<Map<String, dynamic>> jsonList = transactions.map((t) => t.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }
}