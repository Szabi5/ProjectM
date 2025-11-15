// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform; // For platform checks

import 'screens/snapshot_screen.dart'; 
import 'screens/eu_mortgage.dart';
import 'screens/uk_mortgage.dart';
import 'screens/rollover_tab.dart';
import 'screens/overpayment.dart';
import 'screens/refinance_screen.dart'; 
import 'screens/debt_payoff_screen.dart'; 
import 'screens/savings_management_screen.dart';
import 'screens/budget_management_screen.dart'; 
import 'screens/history_screen.dart'; 

import 'services/theme_service.dart';
import 'services/python_bridge.dart';
import 'services/notification_service.dart'; // Import notification service

Future<void> main() async {
  // Ensure Flutter is initialized before we call services
  WidgetsFlutterBinding.ensureInitialized();
  
  // Only run notification code on mobile platforms
  if (Platform.isAndroid || Platform.isIOS) {
    await NotificationService().init();
    await NotificationService().scheduleMonthlyReminder();
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
  State<MortgageApp> createState() => _MortgageAppState();
}

class _MortgageAppState extends State<MortgageApp> {
  int _selectedIndex = 0;
  final bridge = FlutterPythonBridge();

  // --- List of 5 main screens for the bottom bar ---
  static final List<Widget> _screens = <Widget>[
    const SnapshotScreen(), 
    const EuMortgageScreen(),
    const UkMortgageScreen(),
    const RolloverTab(),
    const DebtPayoffScreen(),
  ];

  // --- Titles for the 5 main screens ---
  static const List<String> _screensTitles = <String>[
    'Financial Snapshot',
    'EU Mortgage',
    'UK Mortgage',
    'Rollover',
    'Debts',
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);

    return MaterialApp(
      title: 'Financial Snapshot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      themeMode: themeService.mode,
      home: Scaffold(
        appBar: AppBar(
          title: Text(_screensTitles[_selectedIndex]), // Dynamic title
          centerTitle: true, 
          actions: [
            // --- HISTORY BUTTON ---
            Builder(builder: (ctx) => IconButton(
              icon: const Icon(Icons.history), 
              tooltip: 'View History', 
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const HistoryScreen())),
            )),
            // --- REFINANCE BUTTON ---
            Builder(builder: (ctx) => IconButton(
              icon: const Icon(Icons.monetization_on),
              tooltip: 'Refinance',
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const RefinanceScreen())),
            )),
            // --- SAVINGS BUTTON ---
            Builder(builder: (ctx) => IconButton(
              icon: const Icon(Icons.savings_outlined),
              tooltip: 'Manage Savings', 
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SavingsManagementScreen())),
            )),
            // --- BUDGET BUTTON ---
            Builder(builder: (ctx) => IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Manage Budget',
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const BudgetManagementScreen())),
            )),
            
            // --- "PAYMENTS" CALCULATOR BUTTON ---
            Builder(builder: (ctx) => IconButton(
              icon: const Icon(Icons.calculate_outlined),
              tooltip: 'Payment Calculator',
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => 
                // Re-wrap in a Scaffold so it has its own AppBar
                Scaffold(
                  appBar: AppBar(title: const Text("Payment Calculator")),
                  body: const OverpaymentScreen(), // This is your original Payments tab
                )
              )),
            )),
            
            // --- THEME BUTTON ---
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'light') themeService.setMode(ThemeMode.light);
                if (v == 'dark') themeService.setMode(ThemeMode.dark);
                if (v == 'system') themeService.setMode(ThemeMode.system);
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'light', child: Text('Light')),
                PopupMenuItem(value: 'dark', child: Text('Dark')),
                PopupMenuItem(value: 'system', child: Text('System')),
              ],
              icon: const Icon(Icons.color_lens),
            ),
          ],
        ),
        body: _screens[_selectedIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          
          // --- THIS IS THE FIX ---
          // The typo was here. It was '_onItemTTapped'
          onDestinationSelected: _onItemTapped, 
          // --- END OF FIX ---
          
          destinations: const [
            NavigationDestination(icon: Icon(Icons.account_balance), label: 'Snapshot'),
            NavigationDestination(icon: Icon(Icons.euro), label: 'EU'),
            NavigationDestination(icon: Icon(Icons.currency_pound), label: 'UK'),
            NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Rollover'),
            NavigationDestination(icon: Icon(Icons.credit_card), label: 'Debts'),
          ],
        ),
      ),
      routes: {
        '/refinance': (_) => const RefinanceScreen(),
        '/savings': (_) => const SavingsManagementScreen(),
        '/budget': (_) => const BudgetManagementScreen(),
        '/history': (_) => const HistoryScreen(), 
      },
    );
  }
}