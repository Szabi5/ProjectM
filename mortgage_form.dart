// lib/widgets/mortgage_form.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Defines the data structure that the form will return on submission
class MortgageData {
  final double loanAmount;
  final double annualRate;
  final int years;
  final double propValue;
  final double monthlyOverpay;
  final double overpayPct;
  final double annualLump;
  final int annualLumpMonth;
  final double oneOffLump;
  final int oneOffLumpMonth;
  final String rateChanges;
  final double inflation;

  MortgageData({
    required this.loanAmount,
    required this.annualRate,
    required this.years,
    required this.propValue,
    required this.monthlyOverpay,
    required this.overpayPct,
    required this.annualLump,
    required this.annualLumpMonth,
    required this.oneOffLump,
    required this.oneOffLumpMonth,
    required this.rateChanges,
    required this.inflation,
  });

  // ADDED: toJson method for JSON serialization
  Map<String, dynamic> toJson() => {
    'loan_amount': loanAmount,
    'annual_rate': annualRate,
    'years': years,
    'property_value': propValue,
    'monthly_overpayment': monthlyOverpay,
    'overpayment_pct': overpayPct,
    'annual_lump_sum': annualLump,
    'annual_lump_month': annualLumpMonth,
    'one_off_lump_sum': oneOffLump,
    'one_off_lump_month': oneOffLumpMonth,
    'rate_changes': rateChanges,
    'inflation': inflation,
  };
}

class MortgageInputForm extends StatefulWidget {
  final String currencySymbol;
  final Function(MortgageData data) onRunProjection;

  const MortgageInputForm({
    super.key,
    required this.currencySymbol,
    required this.onRunProjection,
  });

  @override
  State<MortgageInputForm> createState() => _MortgageInputFormState();
}

class _MortgageInputFormState extends State<MortgageInputForm> {
  final _formKey = GlobalKey<FormState>();
  
  final _loanController = TextEditingController(text: '152819.71');
  final _rateController = TextEditingController(text: '4.69');
  final _yearsController = TextEditingController(text: '24');
  final _propvalController = TextEditingController(text: '318000');
  
  final _monthlyOverpayController = TextEditingController(text: '0');
  final _overpayPctController = TextEditingController(text: '0');
  final _annualLumpController = TextEditingController(text: '0');
  final _annualLumpMonthController = TextEditingController(text: '12'); 
  final _oneOffLumpController = TextEditingController(text: '0');
  final _oneOffLumpMonthController = TextEditingController(text: '0');
  
  final _rateChangesController = TextEditingController(text: '');
  final _inflationController = TextEditingController(text: '0');

  Widget _buildNumberField({
    required String label,
    required TextEditingController controller,
    String? suffix,
    int? maxLines = 1,
    bool isInt = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
        inputFormatters: [
          if (isInt) FilteringTextInputFormatter.digitsOnly else FilteringTextInputFormatter.allow(RegExp(r'^\d+[\.]{0,1}\d*')),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        maxLines: maxLines,
      ),
    );
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      final data = MortgageData(
        loanAmount: double.tryParse(_loanController.text) ?? 0.0,
        annualRate: double.tryParse(_rateController.text) ?? 0.0,
        years: int.tryParse(_yearsController.text) ?? 0,
        propValue: double.tryParse(_propvalController.text) ?? 0.0,
        monthlyOverpay: double.tryParse(_monthlyOverpayController.text) ?? 0.0,
        overpayPct: double.tryParse(_overpayPctController.text) ?? 0.0,
        annualLump: double.tryParse(_annualLumpController.text) ?? 0.0,
        annualLumpMonth: int.tryParse(_annualLumpMonthController.text) ?? 12,
        oneOffLump: double.tryParse(_oneOffLumpController.text) ?? 0.0,
        oneOffLumpMonth: int.tryParse(_oneOffLumpMonthController.text) ?? 0,
        rateChanges: _rateChangesController.text,
        inflation: double.tryParse(_inflationController.text) ?? 0.0,
      );
      widget.onRunProjection(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "${widget.currencySymbol} Mortgage",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                const SizedBox(height: 10),
                _buildNumberField(label: 'Loan Amount', controller: _loanController, suffix: widget.currencySymbol),
                _buildNumberField(label: 'Annual Interest Rate (%)', controller: _rateController, suffix: '%'),
                _buildNumberField(label: 'Remaining Years', controller: _yearsController, isInt: true),
                _buildNumberField(label: 'Property Value', controller: _propvalController, suffix: widget.currencySymbol),
                const Divider(),
                const Text(
                  "Overpayment Strategies",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildNumberField(label: 'Monthly Overpayment', controller: _monthlyOverpayController, suffix: widget.currencySymbol),
                _buildNumberField(label: '% of Base Monthly (extra)', controller: _overpayPctController, suffix: '%'),
                _buildNumberField(label: 'Annual Lump Sum', controller: _annualLumpController, suffix: widget.currencySymbol),
                _buildNumberField(label: 'Annual Lump Month (1–12)', controller: _annualLumpMonthController, isInt: true),
                _buildNumberField(label: 'One-off Lump Sum', controller: _oneOffLumpController, suffix: widget.currencySymbol),
                _buildNumberField(label: 'One-off Lump Month (0=off)', controller: _oneOffLumpMonthController, isInt: true),
                const Divider(),
                const Text(
                  "Rates & Inflation",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildNumberField(
                  label: 'Rate changes (e.g. 12:4.5,24:6)',
                  controller: _rateChangesController,
                  suffix: 'Month:Rate',
                  maxLines: 2,
                ),
                _buildNumberField(label: 'Inflation % (optional)', controller: _inflationController, suffix: '%'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                        child: const Text("Run Projection"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Save Settings is a mock feature for now.')),
                          );
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade600, foregroundColor: Colors.white),
                        child: const Text("Save Settings"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}