// lib/models/transaction_item.dart

class TransactionItem {
  final String id;
  final String budgetItemId; // Links to the specific Budget Item (e.g., "Petrol")
  final String categoryId;
  final double amount;
  final DateTime date;

  TransactionItem({
    required this.id,
    required this.budgetItemId,
    required this.categoryId,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'budgetItemId': budgetItemId,
    'categoryId': categoryId,
    'amount': amount,
    'date': date.toIso8601String(),
  };

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      id: json['id'],
      budgetItemId: json['budgetItemId'],
      categoryId: json['categoryId'],
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date']),
    );
  }
}