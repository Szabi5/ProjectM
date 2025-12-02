// lib/models/rollover_chart_data.dart

/// Represents a single point in the amortization schedule for rollover comparison.
class RolloverAmortizationPoint {
  final int month;
  // Balance if Option 1 is chosen
  final double option1Balance;
  // Balance if Option 2 is chosen
  final double option2Balance;

  RolloverAmortizationPoint({
    required this.month,
    required this.option1Balance,
    required this.option2Balance,
  });

  factory RolloverAmortizationPoint.fromJson(Map<String, dynamic> json) {
    return RolloverAmortizationPoint(
      month: json['month'] as int,
      // Updated keys to specifically reference Option 1 and Option 2
      option1Balance: (json['option1_balance'] as num).toDouble(),
      option2Balance: (json['option2_balance'] as num).toDouble(),
    );
  }
}

/// Holds the full list of points for the rollover chart
class RolloverChartData {
  final List<RolloverAmortizationPoint> points;

  RolloverChartData({required this.points});

  factory RolloverChartData.fromJsonList(List<dynamic> jsonList) {
    List<RolloverAmortizationPoint> points = jsonList
        .map((e) => RolloverAmortizationPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    return RolloverChartData(points: points);
  }
}