// lib/models/schedule_data.dart


/// Represents a single row in the yearly amortization schedule summary.
class YearlyScheduleRow {
  final int year;
  final double payment;
  final double principal;
  final double interest;
  final double balance;

  YearlyScheduleRow({
    required this.year,
    required this.payment,
    required this.principal,
    required this.interest,
    required this.balance,
  });

  factory YearlyScheduleRow.fromJson(Map<String, dynamic> json) {
    return YearlyScheduleRow(
      year: json['year'] as int,
      payment: (json['payment'] as num).toDouble(),
      principal: (json['principal'] as num).toDouble(),
      interest: (json['interest'] as num).toDouble(),
      balance: (json['balance'] as num).toDouble(),
    );
  }
}

/// Holds the full list of YearlyScheduleRow for the table.
class AmortizationScheduleData {
  final List<YearlyScheduleRow> yearlySchedule;

  AmortizationScheduleData({required this.yearlySchedule});

  factory AmortizationScheduleData.fromJsonList(List<dynamic> jsonList) {
    List<YearlyScheduleRow> schedule = jsonList
        .map((e) => YearlyScheduleRow.fromJson(e as Map<String, dynamic>))
        .toList();
    return AmortizationScheduleData(yearlySchedule: schedule);
  }
}