// lib/screens/savings_management_screen.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart'; 
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; 
import 'package:uuid/uuid.dart';
import 'package:fl_chart/fl_chart.dart'; // <--- Ensure this is imported
import '../services/savings_service.dart';

// Helper function to convert Hex string to Color object
Color colorFromHex(String hexColor) {
  hexColor = hexColor.toUpperCase().replaceAll("#", "");
  if (hexColor.length == 6) {
    hexColor = "FF" + hexColor;
  }
  return Color(int.parse(hexColor, radix: 16));
}

class SavingsManagementScreen extends StatefulWidget {
  const SavingsManagementScreen({Key? key}) : super(key: key);

  @override
  State<SavingsManagementScreen> createState() => _SavingsManagementScreenState();
}

class _SavingsManagementScreenState extends State<SavingsManagementScreen> {
  final _service = SavingsService();
  bool _isLoading = true;
  List<SavingsPlatform> _platforms = [];
  
  // Controllers and State
  Map<String, TextEditingController> _balanceControllers = {};
  final _conversionRateController = TextEditingController(text: "0.85");

  // Summary State
  double _totalEuSavings = 0.0;
  double _totalGbpSavings = 0.0;
  double _totalCombinedGbp = 0.0;

  // Category State
  List<SavingsCategory> _categories = [];
  Map<String, String> _categoryNameMap = {}; 
  Map<String, Color> _categoryColorMap = {}; 
  Map<String, List<SavingsPlatform>> _groupedPlatforms = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _balanceControllers.values.forEach((controller) => controller.dispose());
    _conversionRateController.dispose();
    super.dispose();
  }
  
  void _addListeners() {
    _conversionRateController.addListener(_calculateSummary);
    _balanceControllers.values.forEach((controller) {
      controller.addListener(_calculateSummary);
    });
  }

  void _removeListeners() {
     _conversionRateController.removeListener(_calculateSummary);
    _balanceControllers.values.forEach((controller) {
      controller.removeListener(_calculateSummary);
    });
  }
  
  void _syncCategoryMaps() {
    _categoryNameMap = {for (var c in _categories) c.id: c.name};
    _categoryColorMap = {for (var c in _categories) c.id: colorFromHex(c.colorHex)};
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; });
    _removeListeners(); 

    final prefs = await SharedPreferences.getInstance();
    
    // 1. Load Categories
    _categories = await _service.loadCategories();
    _syncCategoryMaps();

    // 2. Load Platforms
    final platforms = await _service.loadPlatforms();
    
    _conversionRateController.text = prefs.getString('snapshot_conversion_rate') ?? '0.85';

    _balanceControllers.values.forEach((controller) => controller.dispose());
    _balanceControllers = {
      for (var p in platforms)
        p.id: TextEditingController(text: p.balance.toStringAsFixed(2))
    };

    // 3. Group Platforms
    _groupedPlatforms = platforms.groupListsBy((p) => p.categoryId);

    setState(() {
      _platforms = platforms;
      _isLoading = false;
    });
    
    _calculateSummary();
    _addListeners();
  }

  Future<void> _saveData() async {
    _removeListeners();
    
    for (var platform in _platforms) {
      final balanceText = _balanceControllers[platform.id]?.text ?? '0';
      platform.balance = double.tryParse(balanceText) ?? 0.0;
    }
    
    await _service.savePlatforms(_platforms);
    await _service.saveCategories(_categories);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('snapshot_conversion_rate', _conversionRateController.text);
    
    _addListeners();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Savings data saved!'), backgroundColor: Colors.green),
    );
  }

  void _calculateSummary() {
    double tempEuTotal = 0.0;
    double tempGbpTotal = 0.0;
    final double rate = double.tryParse(_conversionRateController.text) ?? 0.85;

    for (var platform in _platforms) {
      final balance = double.tryParse(_balanceControllers[platform.id]?.text ?? '0') ?? 0.0;
      if (platform.currency == "EUR") {
        tempEuTotal += balance;
      } else {
        tempGbpTotal += balance;
      }
    }
    
    setState(() {
      _totalEuSavings = tempEuTotal;
      _totalGbpSavings = tempGbpTotal;
      _totalCombinedGbp = tempGbpTotal + (tempEuTotal * rate);
    });
  }

  // --- NEW: Savings Distribution & Insights Chart ---
  Widget _buildSavingsDistributionChart() {
    if (_platforms.isEmpty || _totalCombinedGbp == 0) return const SizedBox.shrink();

    final double rate = double.tryParse(_conversionRateController.text) ?? 0.85;

    // 1. Aggregate Totals by Category
    final Map<String, double> categoryTotals = {};
    
    for (var platform in _platforms) {
      double amount = double.tryParse(_balanceControllers[platform.id]?.text ?? '0') ?? 0.0;
      // Convert to GBP for the chart if needed
      if (platform.currency == "EUR") amount *= rate;
      
      categoryTotals[platform.categoryId] = (categoryTotals[platform.categoryId] ?? 0.0) + amount;
    }

    // 2. Prepare Data for Chart
    final List<PieChartSectionData> sections = [];
    final List<Widget> legendItems = [];
    final gbpFormatter = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);

    // Sort categories by amount descending
    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String largestCategoryName = "";
    double largestCategoryAmount = 0.0;

    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final categoryId = entry.key;
      final amount = entry.value;
      
      if (amount <= 0) continue;

      // Track largest for insights
      if (i == 0) {
        largestCategoryAmount = amount;
      }

      final category = _categories.firstWhere((c) => c.id == categoryId, orElse: () => _categories.first);
      if (i == 0) largestCategoryName = category.name;

      final color = _categoryColorMap[categoryId] ?? Colors.grey;
      final percentage = (amount / _totalCombinedGbp) * 100;

      // Chart Section
      sections.add(
        PieChartSectionData(
          value: amount,
          title: '${percentage.toStringAsFixed(0)}%',
          color: color,
          radius: 80,
          titleStyle: TextStyle(
            fontSize: 12, 
            fontWeight: FontWeight.bold, 
            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white
          ),
        ),
      );

      // Legend Item
      legendItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              Icon(Icons.circle, color: color, size: 10),
              const SizedBox(width: 8),
              Text('${category.name}: ${gbpFormatter.format(amount)} (${percentage.toStringAsFixed(1)}%)', 
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // 3. Insights Text
    String insightText = "Your total savings portfolio is valued at **${gbpFormatter.format(_totalCombinedGbp)}**.";
    
    if (largestCategoryName.isNotEmpty) {
      final largestPct = (largestCategoryAmount / _totalCombinedGbp) * 100;
      insightText += "\nYour largest asset allocation is in **$largestCategoryName**, representing ${largestPct.toStringAsFixed(1)}% of your total wealth.";
    }

    // 4. Build Widget
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 16, bottom: 16, left: 12, right: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Asset Allocation & Insights", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const Divider(),
            
            // Pie Chart
            SizedBox(
              height: 200,
              child: sections.isEmpty 
                ? const Center(child: Text('No savings data.')) 
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
            const Text("Asset Legend:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 16, children: legendItems),
            
            const Divider(height: 24),

            // Portfolio Insights Text
            const Text("Portfolio Insights:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(insightText, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // --- Platform Dialog ---
  void _showPlatformDialog({SavingsPlatform? platformToEdit}) {
    final bool isEditing = platformToEdit != null;
    final nameController = TextEditingController(text: isEditing ? platformToEdit.name : '');
    String selectedCurrency = isEditing ? platformToEdit.currency : "GBP"; 
    
    String selectedCategoryId = isEditing 
        ? platformToEdit.categoryId 
        : (_categories.isNotEmpty ? _categories.first.id : 'default-savings-uncategorized');

    if (!_categories.any((c) => c.id == selectedCategoryId)) {
      selectedCategoryId = _categories.isNotEmpty ? _categories.first.id : 'default-savings-uncategorized';
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder( 
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? "Edit Platform" : "Add New Platform"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: "Platform Name (e.g., Wise, Vanguard)"),
                      autofocus: true,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(labelText: "Category"),
                      isExpanded: true,
                      items: _categories.map((SavingsCategory c) {
                        return DropdownMenuItem<String>(
                          value: c.id,
                          child: Row(
                            children: [
                              Icon(Icons.circle, color: colorFromHex(c.colorHex), size: 12),
                              const SizedBox(width: 8),
                              Text(c.name),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newId) => setDialogState(() => selectedCategoryId = newId!),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedCurrency,
                      decoration: const InputDecoration(labelText: "Currency"),
                      items: [
                        const DropdownMenuItem(value: "GBP", child: Text("GBP (£)")),
                        const DropdownMenuItem(value: "EUR", child: Text("EUR (€)")),
                      ],
                      onChanged: (value) => setDialogState(() => selectedCurrency = value!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text;
                    if (name.isNotEmpty) {
                      if (isEditing) {
                        platformToEdit!.name = name;
                        platformToEdit.currency = selectedCurrency;
                        platformToEdit.categoryId = selectedCategoryId;
                      } else {
                        final newPlatform = _service.createNewPlatform(name, selectedCurrency, selectedCategoryId);
                        _platforms.add(newPlatform);
                      }
                      
                      await _service.savePlatforms(_platforms);
                      Navigator.of(context).pop();
                      _loadData(); 
                    }
                  },
                  child: Text(isEditing ? "Save Changes" : "Add"),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _deletePlatform(String id) async {
    _platforms.removeWhere((p) => p.id == id);
    _balanceControllers.remove(id)?.dispose();
    await _service.savePlatforms(_platforms);
    _loadData(); 
  }

  // --- Category Manager ---
  void _showCategoryManager() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Manage Savings Categories"),
              content: SizedBox(
                width: 300,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ..._categories.map((c) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.circle, color: _categoryColorMap[c.id]),
                      title: Text(c.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _editCategory(c, setDialogState), 
                      ),
                      onLongPress: c.id.startsWith('default-') ? null : () => _confirmDeleteCategory(c, setDialogState),
                    )),
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
                  onPressed: () {
                    _saveData(); 
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
      _categories.add(SavingsCategory(
        id: uuid.v4(), 
        name: 'New Asset Class',
        colorHex: '#FF9E9E9E',
      ));
      _syncCategoryMaps();
    });
  }

  void _editCategory(SavingsCategory category, StateSetter setDialogState) {
    TextEditingController nameController = TextEditingController(text: category.name);
    Color pickerColor = _categoryColorMap[category.id]!;
    final bool canDelete = !category.id.startsWith('default-');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInnerDialogState) {
            return AlertDialog(
              title: Text("Edit ${category.name}"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Category Name"),
                  ),
                  const SizedBox(height: 10),
                  BlockPicker(
                    pickerColor: pickerColor,
                    onColorChanged: (color) => setInnerDialogState(() => pickerColor = color),
                  ),
                ],
              ),
              actions: [
                if (canDelete)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _confirmDeleteCategory(category, setDialogState);
                    },
                    child: const Text("Delete", style: TextStyle(color: Colors.red)),
                  ),
                TextButton(
                  onPressed: () {
                    category.name = nameController.text;
                    category.colorHex = '#${pickerColor.value.toRadixString(16).toUpperCase()}';
                    setDialogState(() { 
                      _syncCategoryMaps();
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _confirmDeleteCategory(SavingsCategory category, StateSetter setDialogState) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Category?"),
        content: Text("All items in '${category.name}' will be moved to 'General Savings'. Confirm?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async { 
              final defaultId = _categories.firstWhere((c) => c.name.contains('General'), orElse: () => _categories.first).id;
              
              for (var p in _platforms) {
                if (p.categoryId == category.id) {
                  p.categoryId = defaultId;
                }
              }
              
              setDialogState(() {
                _categories.removeWhere((c) => c.id == category.id);
                _syncCategoryMaps();
              });
              
              await _service.savePlatforms(_platforms);
              await _service.saveCategories(_categories);
              
              if (mounted) await _loadData(); 
              
              Navigator.pop(context); 
              Navigator.pop(context); 
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- Helper Widget for List Tile ---
  Widget _buildPlatformTile(SavingsPlatform platform) {
    final controller = _balanceControllers[platform.id];
    final String prefix = platform.currency == "GBP" ? "£" : "€";
    final categoryColor = _categoryColorMap[platform.categoryId] ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.account_balance_wallet, color: categoryColor),
        title: Text(platform.name, style: TextStyle(color: categoryColor, fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Balance",
              prefixIcon: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Text(prefix, style: const TextStyle(fontSize: 16)),
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        trailing: SizedBox(
          width: 80,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blueGrey),
                onPressed: () => _showPlatformDialog(platformToEdit: platform),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () => _deletePlatform(platform.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Savings"),
        actions: [
          IconButton(
            icon: const Icon(Icons.category),
            onPressed: _showCategoryManager,
            tooltip: "Manage Categories",
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveData,
            tooltip: "Save Savings",
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Summary Card
                SliverToBoxAdapter(
                  child: _buildSummaryCard(),
                ),
                
                // NEW: Distribution Chart & Insights
                SliverToBoxAdapter(
                  child: _buildSavingsDistributionChart(),
                ),
                
                // Grouped List View
                ..._groupedPlatforms.keys.map((categoryId) {
                  final itemsInCategory = _groupedPlatforms[categoryId]!;
                  final category = _categories.firstWhere((c) => c.id == categoryId, orElse: () => _categories.first);
                  final categoryColor = _categoryColorMap[categoryId] ?? Colors.grey;
                  
                  // Calculate total for header
                  double totalGbp = 0.0;
                  final double rate = double.tryParse(_conversionRateController.text) ?? 0.85;

                  for(var item in itemsInCategory) {
                    double amount = double.tryParse(_balanceControllers[item.id]?.text ?? '0') ?? 0.0;
                    if(item.currency == 'EUR') amount = amount * rate;
                    totalGbp += amount;
                  }

                  return SliverToBoxAdapter(
                    child: Card(
                      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
                      child: ExpansionTile(
                        initiallyExpanded: true,
                        leading: Icon(Icons.circle, color: categoryColor, size: 18),
                        title: Text(
                          category.name, 
                          style: TextStyle(fontWeight: FontWeight.bold, color: categoryColor)
                        ),
                        trailing: Text(
                          '£${totalGbp.toStringAsFixed(0)}', // Approx total
                          style: TextStyle(fontWeight: FontWeight.bold, color: categoryColor)
                        ),
                        children: itemsInCategory.map((p) => _buildPlatformTile(p)).toList(),
                      ),
                    ),
                  );
                }),
                
                // Settings Card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 100), // Extra bottom padding for FAB
                    child: Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Settings", style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _conversionRateController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "EUR→GBP Conversion Rate",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPlatformDialog(),
        child: const Icon(Icons.add),
        tooltip: "Add New Platform",
      ),
    );
  }

  Widget _buildSummaryCard() {
    final gbpFormatter = NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 0);
    final eurFormatter = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
    final double rate = double.tryParse(_conversionRateController.text) ?? 0.85;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(12.0),
      color: Colors.deepPurple.shade700,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "TOTAL SAVINGS & ASSETS (GBP)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              gbpFormatter.format(_totalCombinedGbp),
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const Divider(color: Colors.white30, height: 24),
            _buildLegendItem(
              Colors.green.shade300, 
              "UK Assets (GBP)", 
              gbpFormatter.format(_totalGbpSavings)
            ),
            _buildLegendItem(
              Colors.blue.shade300, 
              "EU Assets (EUR)", 
              gbpFormatter.format(_totalEuSavings * rate), 
              originalValue: eurFormatter.format(_totalEuSavings) 
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String title, String gbpValue, {String? originalValue}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(width: 16, height: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, color: Colors.white)),
          ),
          if (originalValue != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                "($originalValue)",
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
            ),
          Text(
            gbpValue,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}