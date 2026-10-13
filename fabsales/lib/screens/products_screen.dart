import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/data_store.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../widgets/lead_picker_dialog.dart';
import '../widgets/product_tile.dart';
import '../widgets/refreshable_list.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _busy = false;

  void _toggle(Product product) {
    setState(() {
      if (!_selected.remove(product.code)) _selected.add(product.code);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _longPress(Product product) {
    setState(() {
      _selecting = true;
      _selected.add(product.code);
    });
  }

  void _clear() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _createOrder() async {
    final store = context.read<DataStore>();
    final auth = context.read<AuthService>();
    final choice = await LeadPickerDialog.show(context, store.leads ?? const []);
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final order = await OrderService.createOrder(
        auth,
        items: _selected.toList(),
        lead: choice.lead?.name,
        newLead: choice.newLead,
      );
      if (!mounted) return;
      _clear();
      _toast(order.isEmpty ? 'Order sent.' : 'Order $order sent for approval.');
      store.refresh();
    } on OrderException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PreferredSizeWidget _appBar() {
    if (!_selecting) return AppBar(title: const Text('Products'));

    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _clear),
      title: Text('${_selected.length} selected'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.appColors.green),
            onPressed: _busy ? null : _createOrder,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create order'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(),
      body: Selector<DataStore, (List<Product>?, String?)>(
        selector: (_, store) => (store.products, store.productsError),
        builder: (context, data, _) => RefreshableList<Product>(
          items: data.$1,
          error: data.$2,
          onRefresh: context.read<DataStore>().refresh,
          emptyText: 'No products found.',
          emptyIcon: Icons.inventory_2_outlined,
          itemBuilder: (context, product) => ProductTile(
            product: product,
            selecting: _selecting,
            selected: _selected.contains(product.code),
            onTap: () {
              if (_selecting) _toggle(product);
            },
            onLongPress: () {
              if (_selecting) {
                _toggle(product);
              } else {
                _longPress(product);
              }
            },
          ),
        ),
      ),
    );
  }
}
