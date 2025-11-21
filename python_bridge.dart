// lib/services/python_bridge.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class FlutterPythonBridge {
  
  //
  // --- THIS IS THE FINAL UPDATE ---
  // It now points to your live Google Cloud Run URL
  //
  static const String _apiEndpoint = 'https://mortgage-simulator-api-533768278832.us-central1.run.app/calculate';
  
  // Core function: Handles the HTTP communication with the Python API
  Future<String> _callPythonAPI(String script, Map<String, dynamic> dataMap) async {
    try {
      final requestBody = jsonEncode({
        'script': script,
        'data': dataMap, // Pass the Map directly, not a string
      });

      final response = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      if (response.statusCode == 200) {
        return response.body;
      } else {
        return jsonEncode({
          'error': 'API Error: Status ${response.statusCode}. Body: ${response.body}',
        });
      }
    } catch (e) {
      return jsonEncode({
        'error': 'Network Error: Cannot connect to Python API. Is the server running? Error: $e',
      });
    }
  }

  /// Public method to run a simulation or calculation
  /// ACCEPTS A Map<String, dynamic>
  Future<String> run(String script, Map<String, dynamic> dataMap) async {
    print("Calling Python API for: $script");
    return _callPythonAPI(script, dataMap);
  }
}