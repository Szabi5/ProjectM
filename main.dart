import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/theme_service.dart';
import 'services/notification_service.dart';

import 'screens/eu_mortgage.dart';
import 'screens/uk_mortgage.dart';
import 'screens/rollover_tab.dart';
import 'screens/overpayment.dart';
import 'screens/debt_payoff_screen.dart';
import 'screens/savings_management_screen.dart';
import 'screens/budget_management_screen.dart';
import 'screens/history_screen.dart';
import 'screens/snapshot_screen.dart';
import 'screens/refinance_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only schedule notifications on mobile devices
  if (Platform.isAndroid || Platform.isIOS) {
    final notificationService = NotificationService();
    await notificationService.scheduleMonthlyReminder();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: const MortgageApp(),
    ),
  );
}

class MortgageApp extends StatefulWidget {
  const MortgageApp({super.key});

  @override
  _MortgageAppState createState() => _MortgageAppState();
}

class _MortgageAppState extends State<MortgageApp> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const EuMortgageScreen(),
    const UkMortgageScreen(),
    const RolloverTab(),
    const OverpaymentScreen(),
    const DebtPayoffScreen(),
    const SavingsManagementScreen(),
    const BudgetManagementScreen(),
    const HistoryScreen(),
    const SnapshotScreen(),
    const RefinanceScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          title: 'Mortgage Simulator',
          theme: themeService.isDarkMode
              ? ThemeData.dark(useMaterial3: true)
              : ThemeData.light(useMaterial3: true),
          home: Scaffold(
            body: _pages[_selectedIndex],
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.euro), label: 'EU Mortgage'),
                NavigationDestination(
                    icon: Icon(Icons.home), label: 'UK Mortgage'),
                NavigationDestination(
                    icon: Icon(Icons.trending_up), label: 'Rollover'),
                NavigationDestination(
                    icon: Icon(Icons.payments), label: 'Overpay'),
                NavigationDestination(
                    icon: Icon(Icons.bar_chart), label: 'Debt'),
                NavigationDestination(
                    icon: Icon(Icons.savings), label: 'Savings'),
                NavigationDestination(
                    icon: Icon(Icons.account_balance_wallet), label: 'Budget'),
                NavigationDestination(
                    icon: Icon(Icons.history), label: 'History'),
                NavigationDestination(
                    icon: Icon(Icons.pie_chart), label: 'Snapshot'),
                NavigationDestination(
                    icon: Icon(Icons.swap_horizontal_circle),
                    label: 'Refinance'),
              ],
            ),
          ),
        );
      },
    );
  }
}
