// lib/services/backup_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// Import services and models required for backup/restore
import 'budget_service.dart'; 
import 'savings_service.dart';
import 'history_service.dart'; 

// NOTE: Assuming BudgetItem, SavingsPlatform, FinancialSnapshot are accessible from the imported service files.

class BackupService {
  final BudgetService _budgetService = BudgetService();
  final SavingsService _savingsService = SavingsService();
  final HistoryService _historyService = HistoryService();
  
  static const String _backupVersion = '1.0';

  Future<Map<String, dynamic>> _collectAllData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Collect all SharedPreferences settings
    final Map<String, dynamic> settings = {};
    final keys = prefs.getKeys();
    
    for (var key in keys) {
      // Collect all app-specific settings (conversion rates, snapshot values, etc.)
      settings[key] = prefs.get(key); 
    }
    
    // 2. Collect serializable service data
    final budgetItems = await _budgetService.loadItems();
    final savingsPlatforms = await _savingsService.loadPlatforms();
    final historySnapshots = await _historyService.loadHistory();

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'version': _backupVersion, 
      'settings': settings,
      'budget': budgetItems.map((i) => i.toJson()).toList(),
      'savings': savingsPlatforms.map((p) => p.toJson()).toList(),
      'history': historySnapshots.map((s) => s.toJson()).toList(),
    };
  }
  
  /// Exports all app data to a JSON file in the user's local directory for manual cloud backup.
  Future<String> exportData() async {
    final data = await _collectAllData();
    // Use an encoder with indent for readability
    final jsonString = JsonEncoder.withIndent('  ').convert(data);
    
    // Get the directory to save the file (Application Documents)
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'financial_backup_${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final filePath = '${directory.path}/$fileName';
    
    final file = File(filePath);
    await file.writeAsString(jsonString);
    
    return filePath;
  }
  
  /// Imports and restores data from a selected JSON backup file.
  Future<void> importData(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception("Selected file does not exist.");
    }
    
    final jsonString = await file.readAsString();
    final Map<String, dynamic> data = jsonDecode(jsonString);
    
    if (data['version'] != _backupVersion) {
      throw Exception("Incompatible backup file version. Expected version $_backupVersion.");
    }
    
    // 1. Restore SharedPreferences settings
    final prefs = await SharedPreferences.getInstance();
    
    (data['settings'] as Map).forEach((key, value) async {
      // Restoration logic must handle all primitive types correctly.
      if (value is bool) await prefs.setBool(key, value);
      else if (value is int) await prefs.setInt(key, value);
      else if (value is double) await prefs.setDouble(key, value);
      else if (value is String) await prefs.setString(key, value);
      else if (value is List) await prefs.setStringList(key, value.cast<String>());
    });
    
    // 2. Restore serializable service data
    final restoredBudget = (data['budget'] as List)
        .map((j) => BudgetItem.fromJson(j))
        .toList();
    final restoredSavings = (data['savings'] as List)
        .map((j) => SavingsPlatform.fromJson(j))
        .toList();
    final restoredHistory = (data['history'] as List)
        .map((j) => FinancialSnapshot.fromJson(j))
        .toList();
        
    // Save to services (overwriting existing data)
    await _budgetService.saveItems(restoredBudget);
    await _savingsService.savePlatforms(restoredSavings);
    await _historyService.saveSnapshotList(restoredHistory); 
  }
}