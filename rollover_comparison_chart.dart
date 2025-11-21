// lib/widgets/rollover_comparison_chart.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/rollover_chart_data.dart';

// Helper Widget for Legend Items (reused from MortgageChart)
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

class RolloverComparisonChart extends StatelessWidget {
  final RolloverChartData data;

  const RolloverComparisonChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.points.isEmpty) {
      return const Center(child: Text("No rollover comparison data to display."));
    }

    // Determine max values for chart scaling
    final maxY = data.points
        .map((p) => p.baselineCombinedBalance)
        .reduce((a, b) => a > b ? a : b);
    final maxX = data.points
        .map((p) => p.month.toDouble())
        .reduce((a, b) => a > b ? a : b);

    // Convert RolloverAmortizationPoint list to FlSpot lists
    final baselineSpots = data.points
        .map((p) => FlSpot(p.month.toDouble(), p.baselineCombinedBalance))
        .toList();
    final rolloverSpots = data.points
        .map((p) => FlSpot(p.month.toDouble(), p.rolloverCombinedBalance))
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
                  // Y-Axis (Balance) - Using GBP as the combined currency
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text("Combined Balance (£)"),
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
                  // Baseline Scenario (Default Color: Blue)
                  LineChartBarData(
                    spots: baselineSpots,
                    isCurved: true,
                    color: Colors.blue.shade400,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                  ),
                  // Rollover Strategy (Highlight Color: Indigo)
                  LineChartBarData(
                    spots: rolloverSpots,
                    isCurved: true,
                    color: Colors.indigo.shade600,
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
          child: Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _ChartLegendItem(color: Colors.blue.shade400, text: "Baseline (Separate Payments)"),
              _ChartLegendItem(color: Colors.indigo.shade600, text: "Rollover Strategy"),
            ],
          ),
        ),
      ],
    );
  }
}