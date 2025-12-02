// lib/services/currency_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

class CurrencyService {
  // Free, open-source API (Frankfurter) - No API Key required
  static const String _baseUrl = 'https://api.frankfurter.app/latest';

  /// Fetches the latest EUR -> GBP rate
  Future<double?> fetchEurToGbpRate() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl?from=EUR&to=GBP'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // The response looks like: {"amount":1.0, "base":"EUR", "date":"2024-...", "rates":{"GBP":0.8543}}
        final double rate = (data['rates']['GBP'] as num).toDouble();
        return rate;
      } else {
        print('Failed to load currency data: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching currency rate: $e');
      return null;
    }
  }
}