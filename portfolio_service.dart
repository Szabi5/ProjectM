// lib/services/portfolio_service.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart'; 
import '../models/investment_holding.dart';

class PortfolioService {
  
  Future<List<InvestmentHolding>> importInvestments() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return [];

      List<InvestmentHolding> allHoldings = [];

      for (var path in result.paths) {
        if (path == null) continue;
        final file = File(path);
        
        // --- FIX: Safe Filename Extraction for Windows ---
        String filename = "Unknown";
        try {
          // Use platform separator to handle Windows paths correctly
          filename = file.path.split(Platform.pathSeparator).last;
          if (filename.contains('.csv')) {
            filename = filename.replaceAll('.csv', '');
          }
        } catch (e) {
          print("Error parsing filename: $e");
        }

        final lines = await file.readAsLines();

        for (int i = 1; i < lines.length; i++) {
          final line = lines[i];
          if (line.trim().isEmpty) continue;
          
          final rawParts = line.split(RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)'));
          final parts = rawParts.map((p) => p.trim().replaceAll('"', '')).toList();

          // --- FIX: Ensure we have data before accessing index 0 ---
          if (parts.isEmpty) continue; 
          
          if (parts.length < 6) continue;
          if (parts[0] == 'Total') continue; 

          allHoldings.add(InvestmentHolding(
            ticker: parts[0],
            name: parts[1],
            investedValue: double.tryParse(parts[2]) ?? 0.0,
            currentValue: double.tryParse(parts[3]) ?? 0.0, 
            profitLoss: double.tryParse(parts[4]) ?? 0.0,
            quantity: double.tryParse(parts[5]) ?? 0.0,
            sourceFile: filename, 
          ));
        }
      }
      return allHoldings;
    } catch (e) {
      print("Error importing CSV: $e");
      return [];
    }
  }

  // ... (Rest of the class remains unchanged: fetchLiveMarketUpdates, generateSuggestions)
  // [Includes the safety checks and USD conversion logic from previous successful iterations]
  
  // --- 2. SMART Live Market Data ---
  Future<List<InvestmentHolding>> fetchLiveMarketUpdates(List<InvestmentHolding> currentHoldings) async {
    List<InvestmentHolding> updatedList = [];
    
    // Fetch USD Rate
    double usdToGbp = 0.79; 
    try {
      YahooFinanceResponse rateResponse = await const YahooFinanceDailyReader().getDailyDTOs('USDGBP=X');
      if (rateResponse.candlesData.isNotEmpty) {
        usdToGbp = rateResponse.candlesData.first.close;
      }
    } catch (e) {
      print("Failed to fetch exchange rate: $e");
    }

    for (var holding in currentHoldings) {
      double referencePrice = holding.currentPrice;
      if (referencePrice == 0) referencePrice = 1.0; 

      List<String> candidates = [holding.ticker];
      if (!holding.ticker.contains('.')) {
        candidates.add('${holding.ticker}.L');
      }

      double? bestNewPrice;
      double minDiffPercent = 100.0; 

      for (var ticker in candidates) {
        try {
          YahooFinanceResponse response = await const YahooFinanceDailyReader().getDailyDTOs(ticker);
          final List<YahooFinanceCandleData> prices = response.candlesData;

          if (prices.isNotEmpty) {
            double latestPrice = prices.first.close; 
            
            // Check 1: Direct
            double diffDirect = (latestPrice - referencePrice).abs();
            double pctDirect = (diffDirect / referencePrice) * 100;

            // Check 2: Pence
            double pricePence = latestPrice / 100.0;
            double diffPence = (pricePence - referencePrice).abs();
            double pctPence = (diffPence / referencePrice) * 100;

            // Check 3: USD
            double priceUsd = latestPrice * usdToGbp;
            double diffUsd = (priceUsd - referencePrice).abs();
            double pctUsd = (diffUsd / referencePrice) * 100;

            if (pctDirect < minDiffPercent) {
              minDiffPercent = pctDirect;
              bestNewPrice = latestPrice;
            }
            if (pctPence < minDiffPercent) {
              minDiffPercent = pctPence;
              bestNewPrice = pricePence;
            }
            if (pctUsd < minDiffPercent) {
              minDiffPercent = pctUsd;
              bestNewPrice = priceUsd;
            }
          }
        } catch (e) {
          // Ignore
        }
      }

      if (bestNewPrice != null && minDiffPercent < 20.0) {
        updatedList.add(holding.copyWithPrice(bestNewPrice));
      } else {
        updatedList.add(holding); 
      }
    }
    
    return updatedList;
  }
  
  Map<String, String> generateSuggestions(List<InvestmentHolding> holdings) {
    if (holdings.isEmpty) return {};
    
    double totalValue = holdings.fold(0, (sum, h) => sum + h.currentValue);
    double targetWeight = 1.0 / holdings.length; 
    
    Map<String, String> suggestions = {};
    
    for (var h in holdings) {
      double diff = h.currentValue - (totalValue * targetWeight);
      if (diff.abs() < (totalValue * 0.01)) {
        suggestions[h.ticker] = "✅ Hold";
      } else if (diff > 0) {
        suggestions[h.ticker] = "🔴 Sell £${diff.toStringAsFixed(0)}";
      } else {
        suggestions[h.ticker] = "🟢 Buy £${diff.abs().toStringAsFixed(0)}";
      }
    }
    return suggestions;
  }
}