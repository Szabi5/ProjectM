// lib/widgets/rollover_form.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'mortgage_form.dart'; // To reuse the MortgageData structure

// Defines the data structure that the Rollover form will return
class RolloverData {
  final MortgageData euData;
  final MortgageData ukData;
  final double fxRateEURtoGBP;
  final int rolloverMonth;
  final double annualInflation;

  RolloverData({
    required this.euData,
    required this.ukData,
    required this.fxRateEURtoGBP,
    required this.rolloverMonth,
    required this.annualInflation,
  });

  // ADDED: toJson method for JSON serialization
  Map<String, dynamic> toJson() => {
    'eu_mortgage_data': euData.toJson(), // Call toJson on nested object
    'uk_mortgage_data': ukData.toJson(), // Call toJson on nested object
    'fx_rate_eur_to_gbp': fxRateEURtoGBP,
    'rollover_month': rolloverMonth,
    'annual_inflation': annualInflation,
  };
}

class RolloverInputForm extends StatefulWidget {
  final Function(RolloverData data) onRunSimulation;

  const RolloverInputForm({
    super.key,
    required this.onRunSimulation,
  });

  @override
  State<RolloverInputForm> createState() => _RolloverInputFormState();
}

class _RolloverInputFormState extends State<RolloverInputForm> {
  final _formKey = GlobalKey<FormState>();

  final _euLoanController = TextEditingController(text: '152819.71');
  final _euRateController = TextEditingController(text: '4.69');
  final _euYearsController = TextEditingController(text: '24');
  final _euOverpayController = TextEditingController(text: '0');

  final _ukLoanController = TextEditingController(text: '180000');
  final _ukRateController = TextEditingController(text: '5.5');
  final _ukYearsController = TextEditingController(text: '20');
  final _ukOverpayController = TextEditingController(text: '0');
  
  final _fxRateController = TextEditingController(text: '0.8500');
  final _rolloverMonthController = TextEditingController(text: '90');
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
      final euData = MortgageData(
        loanAmount: double.tryParse(_euLoanController.text) ?? 0.0,
        annualRate: double.tryParse(_euRateController.text) ?? 0.0,
        years: int.tryParse(_euYearsController.text) ?? 0,
        monthlyOverpay: double.tryParse(_euOverpayController.text) ?? 0.0,
        propValue: 0, overpayPct: 0, annualLump: 0, annualLumpMonth: 0, 
        oneOffLump: 0, oneOffLumpMonth: 0, rateChanges: '', inflation: 0,
      );

      final ukData = MortgageData(
        loanAmount: double.tryParse(_ukLoanController.text) ?? 0.0,
        annualRate: double.tryParse(_ukRateController.text) ?? 0.0,
        years: int.tryParse(_ukYearsController.text) ?? 0,
        monthlyOverpay: double.tryParse(_ukOverpayController.text) ?? 0.0,
        propValue: 0, overpayPct: 0, annualLump: 0, annualLumpMonth: 0, 
        oneOffLump: 0, oneOffLumpMonth: 0, rateChanges: '', inflation: 0,
      );
      
      final rolloverData = RolloverData(
        euData: euData,
        ukData: ukData,
        fxRateEURtoGBP: double.tryParse(_fxRateController.text) ?? 0.0,
        rolloverMonth: int.tryParse(_rolloverMonthController.text) ?? 0,
        annualInflation: double.tryParse(_inflationController.text) ?? 0.0,
      );

      widget.onRunSimulation(rolloverData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 900,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "🇪🇺 EU → 🇬🇧 UK Rollover Simulation Inputs",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const Divider(),
              const SizedBox(height: 10),

              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: 400,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("EU Mortgage Parameters", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildNumberField(label: 'Loan Amount (€)', controller: _euLoanController, suffix: '€'),
                        _buildNumberField(label: 'Annual Rate (%)', controller: _euRateController, suffix: '%'),
                        _buildNumberField(label: 'Remaining Years', controller: _euYearsController, isInt: true),
                        _buildNumberField(label: 'Monthly Overpayment (€)', controller: _euOverpayController, suffix: '€'),
                      ],
                    ),
                  ),

                  SizedBox(
                    width: 400,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("UK Mortgage Parameters", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildNumberField(label: 'Loan Amount (£)', controller: _ukLoanController, suffix: '£'),
                        _buildNumberField(label: 'Annual Rate (%)', controller: _ukRateController, suffix: '%'),
                        _buildNumberField(label: 'Remaining Years', controller: _ukYearsController, isInt: true),
                        _buildNumberField(label: 'Monthly Overpayment (£)', controller: _ukOverpayController, suffix: '£'),
                      ],
                    ),
                  ),
                ],
              ),
              
              const Divider(height: 40),

              const Text(
                "Rollover & Conversion Parameters",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    children: [
                      _buildNumberField(label: 'FX Rate (EUR to GBP)', controller: _fxRateController, suffix: '£ per €'),
                      _buildNumberField(label: 'Rollover Month (e.g., 90)', controller: _rolloverMonthController, isInt: true),
                      _buildNumberField(label: 'Annual Inflation Rate (%)', controller: _inflationController, suffix: '%'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _submitForm,
                icon: const Icon(Icons.swap_horiz),
                label: const Text("Run Rollover Projection"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}