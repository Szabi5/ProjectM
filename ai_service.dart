// lib/services/ai_service.dart

import 'dart:io';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import '../models/investment_holding.dart';

class AIService {
  // We removed the constructor.
  // The service is now "stateless" and connects only when you ask it to.

  Future<String> analyzePortfolio(List<InvestmentHolding> holdings, String strategy) async {
    // 1. Platform Check (Windows/Web safety)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return "⚠️ AI Analysis is currently supported on Android & iOS mobile apps only.\n\n(Firebase Vertex AI does not yet support Desktop).";
    }

    try {
      // 2. Initialize the Connection (Lazy Loading)
      // We do this HERE so if Firebase isn't ready, we catch the error gracefully instead of crashing the app.
      final vertex = FirebaseVertexAI.instanceFor(
        location: "us-central1", // London Data Center
      );

      final model = vertex.generativeModel(
        model: "gemini-2.5-flash",
      );
      print("🤖 Vertex AI Service Instantiated (Gemini 2.5 Flash)");
      
      // 3. Prepare Data
      final total = holdings.fold(0.0, (a, b) => a + b.currentValue);
      final text = StringBuffer();
      text.writeln("Total Value: £${total.toStringAsFixed(0)}");
      text.writeln("Strategy: $strategy");
      text.writeln("Holdings:");

      for (var h in holdings) {
        final pct = total == 0 ? 0 : (h.currentValue / total * 100);
        text.writeln("- ${h.ticker} (${h.name}): £${h.currentValue.toStringAsFixed(0)} (${pct.toStringAsFixed(1)}%)");
      }

      final prompt = """
You are a financial analyst. Analyze this portfolio for a "$strategy" strategy.

Data:
$text

Provide a markdown report with:
1. **Alignment:** Does it fit the strategy?
2. **Risks:** Concentration or sector risks?
3. **Suggestions:** What to buy/sell/hold?
4. **Missing:** What sectors are missing?

Keep it under 300 words. Use emojis.
""";

      // 4. Send to AI
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      return response.text ?? "No response from AI.";

    } catch (e) {
      // 5. Error Handling
      // If Firebase failed to init in main.dart, this will catch it and tell you.
      if (e.toString().contains("no-app") || e.toString().contains("not-initialized")) {
        return "❌ Critical Firebase Error.\n\nThe app failed to connect to Google Services at startup.\n\nPossible fixes:\n1. Ensure 'google-services.json' is in 'android/app/'.\n2. Re-run 'flutterfire configure'.\n3. Uninstall and reinstall the app on your phone.";
      }
      return "❌ AI Error: $e";
    }
  }
}