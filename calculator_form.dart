// lib/widgets/calculator_form.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Defines the data structure for the Payment Calculator
class CalculatorData {
  final double loanAmount;
  final double annualRate;
  final int currentYears; // Original/Current remaining term
  final int targetYears;  // Desired payoff term
  final String currencySymbol;

  CalculatorData({
    required this.loanAmount,
    required this.annualRate,
    required this.currentYears,
    required this.targetYears,
    required this.currencySymbol,
  });

  // ADDED: toJson method for JSON serialization
  Map<String, dynamic> toJson() => {
    'loan_amount': loanAmount,
    'annual_rate': annualRate,
    'current_years': currentYears,
    'target_years': targetYears,
    'currency_symbol': currencySymbol,
  };
}

class CalculatorInputForm extends StatefulWidget {
  final String currencySymbol;
  final Function(CalculatorData data) onRunCalculation;

  const CalculatorInputForm({
    super.key,
    required this.currencySymbol,
    required this.onRunCalculation,
  });

  @override
  State<CalculatorInputForm> createState() => _CalculatorInputFormState();
}

class _CalculatorInputFormState extends State<CalculatorInputForm> {
  final _formKey = GlobalKey<FormState>();

  final _loanController = TextEditingController(text: '152819.71');
  final _rateController = TextEditingController(text: '4.69');
  final _currentYearsController = TextEditingController(text: '24');
  final _targetYearsController = TextEditingController(text: '15');

  Widget _buildNumberField({
    required String label,
    required TextEditingController controller,
    String? suffix,
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
      ),
    );
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      final data = CalculatorData(
        loanAmount: double.tryParse(_loanController.text) ?? 0.0,
        annualRate: double.tryParse(_rateController.text) ?? 0.0,
        currentYears: int.tryParse(_currentYearsController.text) ?? 0,
        targetYears: int.tryParse(_targetYearsController.text) ?? 0,
        currencySymbol: widget.currencySymbol,
      );
      widget.onRunCalculation(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "${widget.currencySymbol} Payment Calculator",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const Divider(),
              const SizedBox(height: 10),
              _buildNumberField(label: 'Loan Amount', controller: _loanController, suffix: widget.currencySymbol),
              _buildNumberField(label: 'Annual Interest Rate', controller: _rateController, suffix: '%'),
              _buildNumberField(label: 'Current Remaining Years (for context)', controller: _currentYearsController, isInt: true),
              const SizedBox(height: 16),
              const Text(
                "Target",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildNumberField(label: 'Target Payoff Years', controller: _targetYearsController, isInt: true),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _submitForm,
                icon: const Icon(Icons.calculate),
                label: const Text("Calculate Required Payment"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade600, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}