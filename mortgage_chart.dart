// lib/widgets/mortgage_chart.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/chart_data.dart';

// Helper Widget for Legend Items
class _ChartLegendItem extends StatelessWidget {
  final Color color;
  final String text;

  const _ChartLegendItem({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class MortgageChart extends StatelessWidget {
  final MortgageChartData data;
  final String currencySymbol;

  const MortgageChart({
    super.key,
    required this.data,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    if (data.points.isEmpty) {
      return const Center(child: Text("No amortization data to display."));
    }

    // Determine max values for chart scaling
    final maxY = data.points
        .map((p) => p.baselineBalance)
        .reduce((a, b) => a > b ? a : b);
    final maxX = data.points
        .map((p) => p.month.toDouble())
        .reduce((a, b) => a > b ? a : b);

    // Convert AmortizationPoint list to FlSpot lists
    final baselineSpots = data.points
        .map((p) => FlSpot(p.month.toDouble(), p.baselineBalance))
        .toList();
    final overpaySpots = data.points
        .map((p) => FlSpot(p.month.toDouble(), p.overpayBalance))
        .toList();

    return Column(
      children: [
        // 1. The Chart Itself
        AspectRatio(
          aspectRatio: 1.7, 
          child: Padding(
            padding: const EdgeInsets.only(right: 18, left: 12, top: 24, bottom: 12),
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  // X-Axis (Months)
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text("Months"),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 60, // Show a label every 60 months (5 years)
                      getTitlesWidget: (value, meta) {
                        return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  // Y-Axis (Balance)
                  leftTitles: AxisTitles(
                    axisNameWidget: Text("Balance ($currencySymbol)"),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: maxY / 3, // Show roughly 3 ticks
                      getTitlesWidget: (value, meta) {
                        return Text('${(value / 1000).toInt()}k', style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                minX: 0,
                maxX: maxX,
                minY: 0,
                maxY: maxY * 1.05,
                lineBarsData: [
                  // Baseline Mortgage Line (Red)
                  LineChartBarData(
                    spots: baselineSpots,
                    isCurved: true,
                    color: Colors.red.shade400,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                  ),
                  // Overpayment Mortgage Line (Green)
                  LineChartBarData(
                    spots: overpaySpots,
                    isCurved: true,
                    color: Colors.green.shade400,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // 2. The Legend
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ChartLegendItem(color: Colors.red.shade400, text: "Baseline"),
              const SizedBox(width: 20),
              _ChartLegendItem(color: Colors.green.shade400, text: "With Overpayment"),
            ],
          ),
        ),
      ],
    );
  }
}