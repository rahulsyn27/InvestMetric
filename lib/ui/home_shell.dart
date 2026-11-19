import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/providers.dart';

import 'calendar_screen.dart';
import 'family_screen.dart';
import 'holdings_screen.dart';
import 'home_screen.dart';
import 'interest_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    // Keeps today's value snapshot up to date (for returns by period).
    ref.watch(snapshotRecorderProvider);
    final pages = [
      HomeScreen(onOpenTab: _go),
      const HoldingsScreen(),
      const CalendarScreen(),
      const InterestScreen(),
      const FamilyScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Holdings',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Tax',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Family',
          ),
        ],
      ),
    );
  }
}

/// Tab indexes, for [HomeScreen.onOpenTab].
abstract final class Tabs {
  static const holdings = 1;
  static const calendar = 2;
  static const interest = 3;
  static const family = 4;
}
