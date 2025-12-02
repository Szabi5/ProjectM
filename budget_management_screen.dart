// lib/screens/budget_management_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:uuid/uuid.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/budget_service.dart';
import '../services/transaction_service.dart';
import '../models/transaction_item.dart';
import '../models/budget_report_data.dart';
import '../utils/pdf_generator.dart' as pdf_util;

/// Helpers
Color colorFromHex(String hexColor) {
  hexColor = hexColor.toUpperCase().replaceAll("#", "");
  if (hexColor.length == 6) hexColor = "FF$hexColor";
  return Color(int.parse(hexColor, radix: 16));
}

class BudgetManagementScreen extends StatefulWidget {
  const BudgetManagementScreen({Key? key}) : super(key: key);

  @override
  State<BudgetManagementScreen> createState() => BudgetManagementScreenState();
}

class BudgetManagementScreenState extends State<BudgetManagementScreen> {
  final _budgetService = BudgetService();
  final _transactionService = TransactionService();

  // Core state
  bool _isLoading = true;
  List<BudgetItem> _items = [];
  Map<String, TextEditingController> _amountControllers = {};

  // Cash-flow numbers (in GBP)
  double _totalMonthlyIncome = 0.0;
  double _totalMonthlyExpenses = 0.0;
  double _monthlySurplus = 0.0;

  // EUR→GBP conversion
  final _conversionRateController = TextEditingController(text: "0.85");

  // Categories
  List<Category> _categories = [];
  Map<String, String> _categoryNameMap = {};
  Map<String, Color> _categoryColorMap = {};
  Map<String, List<BudgetItem>> _groupedItems = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountControllers.values.forEach((c) => c.dispose());
    _conversionRateController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Loading & Summary
  // ────────────────────────────────────────────────────────────────────────────

  void _addListeners() {
    _conversionRateController.addListener(_calculateSummary);
    _amountControllers.values.forEach((c) {
      c.addListener(_calculateSummary);
    });
  }

  void _removeListeners() {
    _conversionRateController.removeListener(_calculateSummary);
    _amountControllers.values.forEach((c) {
      c.removeListener(_calculateSummary);
    });
  }

  void _syncCategoryMaps() {
    _categoryNameMap = {for (var c in _categories) c.id: c.name};
    _categoryColorMap = {
      for (var c in _categories) c.id: colorFromHex(c.colorHex)
    };
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _removeListeners();

    final prefs = await SharedPreferences.getInstance();
    final savedRate = prefs.getString('snapshot_conversion_rate');
    if (savedRate != null && savedRate.isNotEmpty) {
      _conversionRateController.text = savedRate;
    }

    _categories = await _budgetService.loadCategories();
    _syncCategoryMaps();

    final items = await _budgetService.loadItems();

    // Rebuild controllers
    _amountControllers.values.forEach((c) => c.dispose());
    _amountControllers = {
      for (var i in items)
        i.id: TextEditingController(text: i.amount.toStringAsFixed(2))
    };

    // Group items by category for UI
    _groupedItems = items.groupListsBy((item) => item.categoryId);
    _groupedItems = Map.fromEntries(
      _groupedItems.entries.toList()
        ..sort((a, b) {
          final categoryA = _categories.firstWhere(
            (c) => c.id == a.key,
            orElse: () => _categories.first,
          );
          final categoryB = _categories.firstWhere(
            (c) => c.id == b.key,
            orElse: () => _categories.first,
          );
          return categoryA.type.index.compareTo(categoryB.type.index);
        }),
    );

    setState(() {
      _items = items;
      _isLoading = false;
    });

    _calculateSummary();
    _addListeners();
  }

  Future<void> _saveData() async {
    _removeListeners();

    for (var item in _items) {
      final amountText = _amountControllers[item.id]?.text ?? '0';
      item.amount = double.tryParse(amountText) ?? 0.0;
    }

    await _budgetService.saveItems(_items);
    await _budgetService.saveCategories(_categories);

    _addListeners();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Budget items saved!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  double _toMonthlyGbp(BudgetItem item, double rawAmount) {
    double monthly = rawAmount;
    switch (item.frequency) {
      case BudgetFrequency.Weekly:
        monthly *= 4.3333;
        break;
      case BudgetFrequency.Quarterly:
        monthly /= 3.0;
        break;
      case BudgetFrequency.Yearly:
        monthly /= 12.0;
        break;
      case BudgetFrequency.Monthly:
        break;
    }

    if (item.currency == "EUR") {
      final rate = double.tryParse(_conversionRateController.text) ?? 0.85;
      monthly *= rate;
    }
    return monthly;
  }

  void _calculateSummary() {
    double income = 0.0;
    double expenses = 0.0;

    for (var item in _items) {
      final raw = double.tryParse(
            _amountControllers[item.id]?.text ?? '0',
          ) ??
          0.0;
      final monthlyGbp = _toMonthlyGbp(item, raw);

      if (item.type == BudgetItemType.Income) {
        income += monthlyGbp;
      } else {
        expenses += monthlyGbp;
      }
    }

    setState(() {
      _totalMonthlyIncome = income;
      _totalMonthlyExpenses = expenses;
      _monthlySurplus = income - expenses;
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Quick Add (called from FAB + Quick Action)
  // ────────────────────────────────────────────────────────────────────────────

  /// Public method used by the GlobalKey from `main.dart`
  void showQuickAddDialog() {
    if (_isLoading) {
      Future.delayed(const Duration(milliseconds: 200), showQuickAddDialog);
      return;
    }

    // Find all variable-expense items
    final variableItems = _items.where((item) {
      final cat = _categories.firstWhere(
        (c) => c.id == item.categoryId,
        orElse: () => _categories.first,
      );
      return cat.isVariable;
    }).toList();

    if (variableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No variable categories found. Edit a category and mark it as "Variable" (e.g. Groceries).',
          ),
        ),
      );
      return;
    }

    BudgetItem? selectedItem = variableItems.first;
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currencySymbol =
                selectedItem?.currency == 'EUR' ? '€' : '£';

            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              scrollable: true,
              title: Row(
                children: [
                  const Icon(Icons.flash_on, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Quick Add Expense",
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Select a variable expense to top up (e.g. Petrol, Shopping):",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<BudgetItem>(
                      value: selectedItem,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Expense Item",
                        border: OutlineInputBorder(),
                      ),
                      items: variableItems.map((item) {
                        return DropdownMenuItem(
                          value: item,
                          child: Text(item.name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedItem = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: "Amount Spent ($currencySymbol)",
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final addedAmount =
                        double.tryParse(amountController.text);
                    if (addedAmount == null || selectedItem == null) return;

                    final controller =
                        _amountControllers[selectedItem!.id];
                    final currentAmount =
                        double.tryParse(controller?.text ?? '0') ?? 0.0;
                    final newTotal = currentAmount + addedAmount;

                    controller?.text = newTotal.toStringAsFixed(2);
                    selectedItem!.amount = newTotal;

                    await _budgetService.saveItems(_items);

                    final transaction = TransactionItem(
                      id: const Uuid().v4(),
                      budgetItemId: selectedItem!.id,
                      categoryId: selectedItem!.categoryId,
                      amount: addedAmount,
                      date: DateTime.now(),
                    );
                    await _transactionService.saveTransaction(transaction);

                    _calculateSummary();

                    if (!mounted) return;
                    Navigator.pop(dialogContext);

                    final sym =
                        selectedItem!.currency == 'EUR' ? '€' : '£';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Added $sym${addedAmount.toStringAsFixed(2)} to ${selectedItem!.name}",
                        ),
                      ),
                    );
                  },
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Item & Category Management Dialogs
  // (lightly cleaned but behaviour the same)
  // ────────────────────────────────────────────────────────────────────────────

  void _showItemDialog({BudgetItem? itemToEdit}) {
    final isEditing = itemToEdit != null;
    final nameController =
        TextEditingController(text: isEditing ? itemToEdit!.name : '');
    String selectedCurrency =
        isEditing ? itemToEdit!.currency : "GBP";
    BudgetItemType selectedType =
        isEditing ? itemToEdit!.type : BudgetItemType.Expense;
    BudgetFrequency selectedFrequency =
        isEditing ? itemToEdit!.frequency : BudgetFrequency.Monthly;
    String selectedCategoryId = isEditing
        ? itemToEdit!.categoryId
        : _categories.firstWhere(
              (c) => c.name == 'Uncategorized',
              orElse: () => _categories.first,
            ).id;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredCategories =
                _categories.where((c) => c.type == selectedType).toList();

            if (!filteredCategories
                .any((c) => c.id == selectedCategoryId)) {
              selectedCategoryId = filteredCategories.isNotEmpty
                  ? filteredCategories.first.id
                  : _categories.first.id;
            }

            return AlertDialog(
              scrollable: true,
              title: Text(
                isEditing ? "Edit ${itemToEdit!.name}" : "Add New Item",
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Item Name",
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Type:"),
                        Radio<BudgetItemType>(
                          value: BudgetItemType.Income,
                          groupValue: selectedType,
                          onChanged: (val) {
                            if (val == null) return;
                            setDialogState(() {
                              selectedType = val;
                              selectedCategoryId = _categories
                                  .firstWhere(
                                    (c) => c.type == selectedType,
                                    orElse: () => _categories.first,
                                  )
                                  .id;
                            });
                          },
                        ),
                        const Text("Inc"),
                        Radio<BudgetItemType>(
                          value: BudgetItemType.Expense,
                          groupValue: selectedType,
                          onChanged: (val) {
                            if (val == null) return;
                            setDialogState(() {
                              selectedType = val;
                              selectedCategoryId = _categories
                                  .firstWhere(
                                    (c) => c.type == selectedType,
                                    orElse: () => _categories.first,
                                  )
                                  .id;
                            });
                          },
                        ),
                        const Text("Exp"),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedCategoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Category",
                      ),
                      items: filteredCategories.map((c) {
                        return DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        );
                      }).toList(),
                      onChanged: (newId) {
                        if (newId == null) return;
                        setDialogState(() => selectedCategoryId = newId);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedCurrency,
                      decoration: const InputDecoration(labelText: "Currency"),
                      items: const [
                        DropdownMenuItem(
                          value: "GBP",
                          child: Text("GBP (£)"),
                        ),
                        DropdownMenuItem(
                          value: "EUR",
                          child: Text("EUR (€)"),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setDialogState(() => selectedCurrency = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<BudgetFrequency>(
                      value: selectedFrequency,
                      decoration:
                          const InputDecoration(labelText: "Frequency"),
                      items: BudgetFrequency.values.map((f) {
                        return DropdownMenuItem(
                          value: f,
                          child: Text(f.toString().split('.').last),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setDialogState(() => selectedFrequency = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;

                    if (isEditing) {
                      itemToEdit!
                        ..name = name
                        ..currency = selectedCurrency
                        ..type = selectedType
                        ..frequency = selectedFrequency
                        ..categoryId = selectedCategoryId;
                    } else {
                      final newItem = _budgetService.createNewItem(
                        name,
                        selectedCurrency,
                        selectedType,
                        selectedFrequency,
                        categoryId: selectedCategoryId,
                      );
                      _items.add(newItem);
                    }

                    await _budgetService.saveItems(_items);
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    _loadData();
                  },
                  child: Text(isEditing ? "Save Changes" : "Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteItem(String id) async {
    _items.removeWhere((p) => p.id == id);
    _amountControllers.remove(id)?.dispose();
    await _budgetService.saveItems(_items);
    _loadData();
  }

  void _showCategoryManager() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              title: const Text("Manage Categories"),
              content: SizedBox(
                width: 320,
                child: ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    ..._categories.map(
                      (c) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.circle,
                          color: _categoryColorMap[c.id],
                        ),
                        title: Text(c.name),
                        subtitle: c.isVariable
                            ? const Text(
                                "Variable (Quick Add enabled)",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.amber,
                                ),
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () =>
                              _editCategory(c, setDialogState),
                        ),
                        onLongPress: c.id.startsWith('default-')
                            ? null
                            : () => _confirmDeleteCategory(
                                  c,
                                  setDialogState,
                                ),
                      ),
                    ),
                    const Divider(),
                    ElevatedButton.icon(
                      onPressed: () => _addNewCategory(setDialogState),
                      icon: const Icon(Icons.add),
                      label: const Text("Add New Category"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await _saveData();
                    if (!mounted) return;
                    Navigator.of(context).pop();
                  },
                  child: const Text("Done"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addNewCategory(StateSetter setDialogState) {
    final uuid = const Uuid();
    setDialogState(() {
      _categories.add(
        Category(
          id: uuid.v4(),
          name: 'New Category',
          colorHex: '#FF757575',
          type: BudgetItemType.Expense,
        ),
      );
      _syncCategoryMaps();
    });
  }

  void _editCategory(Category category, StateSetter setDialogState) {
    final nameController = TextEditingController(text: category.name);
    Color pickerColor = _categoryColorMap[category.id]!;
    bool isVariable = category.isVariable;
    final bool canDelete = !category.id.startsWith('default-');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            return AlertDialog(
              scrollable: true,
              title: Text(
                canDelete
                    ? "Edit Category: ${category.name}"
                    : "View Category: ${category.name}",
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Category Name",
                      ),
                    ),
                    const SizedBox(height: 10),
                    BlockPicker(
                      pickerColor: pickerColor,
                      onColorChanged: (color) =>
                          setInnerState(() => pickerColor = color),
                    ),
                    SwitchListTile(
                      title: const Text("Variable Expense?"),
                      subtitle: const Text(
                        "Enable 'Quick Add' for items in this category.",
                      ),
                      value: isVariable,
                      onChanged: (val) =>
                          setInnerState(() => isVariable = val),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Type:"),
                        Radio<BudgetItemType>(
                          value: BudgetItemType.Income,
                          groupValue: category.type,
                          onChanged: (val) => setInnerState(
                            () => category.type = val!,
                          ),
                        ),
                        const Text("Income"),
                        Radio<BudgetItemType>(
                          value: BudgetItemType.Expense,
                          groupValue: category.type,
                          onChanged: (val) => setInnerState(
                            () => category.type = val!,
                          ),
                        ),
                        const Text("Expense"),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (canDelete)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _confirmDeleteCategory(category, setDialogState);
                    },
                    child: const Text(
                      "Delete",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    category.name = nameController.text.trim();
                    category.colorHex =
                        '#${pickerColor.value.toRadixString(16).toUpperCase()}';
                    category.isVariable = isVariable;

                    setDialogState(() {
                      _syncCategoryMaps();
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  

  // ────────────────────────────────────────────────────────────────────────────
  // PDF Export
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _exportBudgetReport() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No budget items to report.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      _calculateSummary();

      final reportDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final summary = {
        'totalMonthlyIncome': _totalMonthlyIncome,
        'totalMonthlyExpenses': _totalMonthlyExpenses,
        'monthlySurplus': _monthlySurplus,
        'conversionRate':
            double.tryParse(_conversionRateController.text) ?? 0.85,
        'reportDate': reportDate,
      };

      final records = _items.map((item) {
        final category = _categories.firstWhere(
          (c) => c.id == item.categoryId,
          orElse: () => _categories.first,
        );
        return {
          'id': item.id,
          'name': item.name,
          'amount': double.tryParse(
                _amountControllers[item.id]?.text ?? '0',
              ) ??
              0.0,
          'currency': item.currency,
          'type': item.type.toString().split('.').last,
          'frequency': item.frequency.toString().split('.').last,
          'categoryName': category.name,
          'categoryColorHex': category.colorHex,
        };
      }).toList();

      final data = BudgetReportData(
        reportTitle: "Monthly Budget and Cash Flow Report",
        summary: summary,
        records: records,
        categories: _categories.map((c) => c.toJson()).toList(),
      );

      final pdfBytes = await pdf_util.generateBudgetReport(data);
      pdf_util.viewPdf(
        context,
        pdfBytes,
        'Budget_Report_$reportDate.pdf',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Budget Report Generated!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // UI Builders
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildBudgetItemListTile(BudgetItem item) {
    final controller = _amountControllers[item.id];
    final prefix = item.currency == "GBP" ? "£" : "€";
    final categoryColor = _categoryColorMap[item.categoryId] ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          item.type == BudgetItemType.Income
              ? Icons.arrow_upward
              : Icons.arrow_downward,
          color: categoryColor,
        ),
        title: Text(
          item.name,
          style: TextStyle(color: categoryColor),
        ),
        subtitle: TextFormField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: "${item.frequency.toString().split('.').last} Amount",
            prefixIcon: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Text(
                prefix,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        trailing: SizedBox(
          width: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blueGrey),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                onPressed: () => _showItemDialog(itemToEdit: item),
              ),
              IconButton(
                icon:
                    const Icon(Icons.delete_outline, color: Colors.grey),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                onPressed: () => _deleteItem(item.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final gbp = NumberFormat.currency(
      locale: 'en_GB',
      symbol: '£',
      decimalDigits: 0,
    );
    final surplusColor =
        _monthlySurplus >= 0 ? Colors.green.shade600 : Colors.red.shade600;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(12),
      color: Colors.blueGrey.shade800,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "MONTHLY CASH FLOW (GBP)",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              gbp.format(_monthlySurplus),
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: surplusColor,
              ),
            ),
            const Divider(color: Colors.white30, height: 24),
            _buildLegendItem(
              Colors.green.shade300,
              "Total Income",
              gbp.format(_totalMonthlyIncome),
            ),
            _buildLegendItem(
              Colors.red.shade300,
              "Total Expenses",
              gbp.format(_totalMonthlyExpenses),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 16, height: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetSummaryChart() {
    final expenseItems =
        _items.where((i) => i.type == BudgetItemType.Expense).toList();
    if (expenseItems.isEmpty) return const SizedBox.shrink();

    final expenseGroups = expenseItems.groupListsBy((i) => i.categoryId);

    double totalExpense = 0.0;
    expenseItems.forEach((item) {
      final raw =
          double.tryParse(_amountControllers[item.id]?.text ?? '0') ?? 0.0;
      totalExpense += _toMonthlyGbp(item, raw);
    });

    if (totalExpense == 0) return const SizedBox.shrink();

    final gbp = NumberFormat.currency(
      locale: 'en_GB',
      symbol: '£',
      decimalDigits: 0,
    );

    final sections = <PieChartSectionData>[];
    final legend = <Widget>[];
    String largestCategory = '';
    double largestAmount = 0;

    final sortedGroups = expenseGroups.entries.toList()
      ..sort(
        (a, b) => b.value.fold<double>(
              0,
              (sum, i) =>
                  sum +
                  _toMonthlyGbp(
                    i,
                    double.tryParse(
                          _amountControllers[i.id]?.text ?? '0',
                        ) ??
                        0.0,
                  ),
            ).compareTo(
              a.value.fold<double>(
                0,
                (sum, i) =>
                    sum +
                    _toMonthlyGbp(
                      i,
                      double.tryParse(
                            _amountControllers[i.id]?.text ?? '0',
                          ) ??
                          0.0,
                    ),
              ),
            ),
      );

    for (var entry in sortedGroups) {
      final categoryId = entry.key;
      final items = entry.value;
      final category = _categories.firstWhere(
        (c) => c.id == categoryId,
        orElse: () => _categories.first,
      );
      final color = _categoryColorMap[categoryId] ?? Colors.grey;

      double categoryTotal = 0;
      for (var item in items) {
        final raw =
            double.tryParse(_amountControllers[item.id]?.text ?? '0') ??
                0.0;
        categoryTotal += _toMonthlyGbp(item, raw);
      }
      if (categoryTotal == 0) continue;

      if (categoryTotal > largestAmount) {
        largestAmount = categoryTotal;
        largestCategory = category.name;
      }

      final pct = (categoryTotal / totalExpense) * 100;

      sections.add(
        PieChartSectionData(
          value: categoryTotal,
          title: '${pct.toStringAsFixed(0)}%',
          color: color,
          radius: 80,
          titleStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color:
                color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          ),
        ),
      );

      legend.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.circle, color: color, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${category.name}: ${gbp.format(categoryTotal)} (${pct.toStringAsFixed(1)}%)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hasSurplus = _monthlySurplus >= 0;
    String summaryText;
    if (hasSurplus) {
      summaryText =
          'Your monthly cash flow shows a surplus of ${gbp.format(_monthlySurplus)}. Great job keeping expenses below income.';
    } else {
      summaryText =
          'Warning: Your current cash flow shows a deficit of ${gbp.format(_monthlySurplus.abs())}. Review your expenses carefully.';
    }

    if (largestCategory.isNotEmpty) {
      summaryText +=
          '\nYour largest expense category is **$largestCategory**, totalling ${gbp.format(largestAmount)} each month.';
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Expense Distribution & Insights",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const Divider(),
            SizedBox(
              height: 200,
              child: sections.isEmpty
                  ? const Center(
                      child: Text('No expenses recorded for analysis.'),
                    )
                  : PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: sections,
                        borderData: FlBorderData(show: false),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Category Legend:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: legend,
            ),
            const Divider(height: 30),
            const Text(
              "Budget Insights:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              summaryText,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Scaffold
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Income & Expenses"),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics, color: Colors.white),
            tooltip: "AI Budget Insights",
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Scroll down to view Budget Insights section.'),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Export PDF Report",
            onPressed: _exportBudgetReport,
          ),
          IconButton(
            icon: const Icon(Icons.category),
            tooltip: "Manage Categories",
            onPressed: _showCategoryManager,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: "Save Budget",
            onPressed: _saveData,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: "quick_add_btn",
            onPressed: showQuickAddDialog,
            icon: const Icon(Icons.flash_on),
            label: const Text("Quick Add"),
            backgroundColor: Colors.amber.shade700,
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "add_item_btn",
            onPressed: () => _showItemDialog(),
            tooltip: "Add New Item",
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildSummaryCard()),
                SliverToBoxAdapter(child: _buildBudgetSummaryChart()),
                ..._groupedItems.keys.map((categoryId) {
                  final itemsInCategory = _groupedItems[categoryId]!;
                  final category = _categories.firstWhere(
                    (c) => c.id == categoryId,
                    orElse: () => _categories.first,
                  );
                  final categoryColor =
                      _categoryColorMap[categoryId] ?? Colors.grey;
                  final categoryTotal = itemsInCategory.fold<double>(
                    0.0,
                    (sum, item) =>
                        sum +
                        (double.tryParse(
                              _amountControllers[item.id]?.text ?? '0',
                            ) ??
                            0.0),
                  );
                  final currency = itemsInCategory.first.currency;
                  final prefix = currency == "GBP" ? "£" : "€";
                  final isIncomeGroup =
                      category.type == BudgetItemType.Income;

                  return SliverToBoxAdapter(
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ExpansionTile(
                        leading: Icon(
                          isIncomeGroup
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: categoryColor,
                          size: 18,
                        ),
                        title: Text(
                          category.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: categoryColor,
                          ),
                        ),
                        trailing: Text(
                          '$prefix${categoryTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: categoryColor,
                          ),
                        ),
                        children: itemsInCategory
                            .map(_buildBudgetItemListTile)
                            .toList(),
                      ),
                    ),
                  );
                }),
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: 80),
                ),
              ],
            ),
    );
  }
}
