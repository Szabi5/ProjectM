// lib/services/scenario_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MortgageScenario {
  final String id;
  final String name;
  final DateTime createdAt;
  final Map<String, dynamic> payload; // raw input fields (loan, rate, years, ...)

  MortgageScenario({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'payload': payload,
      };

  factory MortgageScenario.fromJson(Map<String, dynamic> json) {
    return MortgageScenario(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
    );
  }
}

class ScenarioService {
  static const _storageKey = 'saved_mortgage_scenarios';

  Future<List<MortgageScenario>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    final List<dynamic> arr = jsonDecode(raw);
    return arr.map((e) => MortgageScenario.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveScenario(MortgageScenario s) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    // Replace if same id
    final idx = all.indexWhere((x) => x.id == s.id);
    if (idx >= 0) {
      all[idx] = s;
    } else {
      all.add(s);
    }
    await prefs.setString(_storageKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<void> deleteScenario(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    all.removeWhere((s) => s.id == id);
    await prefs.setString(_storageKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<MortgageScenario?> getById(String id) async {
    final all = await loadAll();
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }
}