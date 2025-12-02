// lib/models/chart_data.dart

// Represents a single point in the amortization schedule
class AmortizationPoint {
  final int month;
  final double baselineBalance;
  final double overpayBalance;

  AmortizationPoint({
    required this.month,
    required this.baselineBalance,
    required this.overpayBalance,
  });

  factory AmortizationPoint.fromJson(Map<String, dynamic> json) {
    return AmortizationPoint(
      month: json['month'] as int,
      // Use toDouble() to safely handle int or num from JSON
      baselineBalance: (json['baseline_balance'] as num).toDouble(),
      overpayBalance: (json['overpay_balance'] as num).toDouble(),
    );
  }
}

// Holds the full list of points for the chart
class MortgageChartData {
  final List<AmortizationPoint> points;

  MortgageChartData({required this.points});

  factory MortgageChartData.fromJsonList(List<dynamic> jsonList) {
    List<AmortizationPoint> points = jsonList
        .map((e) => AmortizationPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    return MortgageChartData(points: points);
  }
}