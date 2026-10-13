import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/data_store.dart';
import 'orders_screen.dart';
import 'home_screen.dart';
import 'leads_screen.dart';
import 'products_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DataStore>(
      create: (ctx) => DataStore(ctx.read<AuthService>())..start(),
      child: const _ShellView(),
    );
  }
}

class _ShellView extends StatefulWidget {
  const _ShellView();

  @override
  State<_ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<_ShellView> {
  static const _titles = ['Home', 'Leads', 'Orders', 'Products', 'Profile'];

  int _index = 0;

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        appBar: _index == 0 || _index == 3 ? null : AppBar(title: Text(_titles[_index])),
        body: IndexedStack(
          index: _index,
          children: [
            HomeScreen(onOpenLeads: () => _select(1)),
            const LeadsScreen(),
            const OrdersScreen(),
            const ProductsScreen(),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_alt_outlined),
              selectedIcon: Icon(Icons.people_alt_rounded),
              label: 'Leads',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'Products',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
