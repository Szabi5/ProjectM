// lib/models/investment_holding.dart

class InvestmentHolding {
  final String ticker;
  final String name;
  final double investedValue;
  final double currentValue;
  final double quantity;
  final double profitLoss;
  final String sourceFile; // <--- NEW FIELD

  double get currentPrice => quantity > 0 ? currentValue / quantity : 0.0;
  double get performancePct => investedValue > 0 ? (profitLoss / investedValue) * 100 : 0.0;

  InvestmentHolding({
    required this.ticker,
    required this.name,
    required this.investedValue,
    required this.currentValue,
    required this.quantity,
    required this.profitLoss,
    required this.sourceFile, // <--- NEW REQUIRED
  });

  // copyWithPrice needs to keep the sourceFile
  InvestmentHolding copyWithPrice(double newPrice) {
    final newValue = newPrice * quantity;
    final newPL = newValue - investedValue;
    return InvestmentHolding(
      ticker: ticker,
      name: name,
      investedValue: investedValue,
      currentValue: newValue,
      quantity: quantity,
      profitLoss: newPL,
      sourceFile: sourceFile, // <--- KEEP SOURCE
    );
  }
}