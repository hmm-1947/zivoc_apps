import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../services/data_store.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/refreshable_list.dart';
import '../widgets/status_chip.dart';
import '../widgets/surface_card.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<DataStore, (List<Order>?, String?)>(
      selector: (_, store) => (store.orders, store.ordersError),
      builder: (context, data, _) => RefreshableList<Order>(
        items: data.$1,
        error: data.$2,
        onRefresh: context.read<DataStore>().refresh,
        emptyText: 'No orders yet.',
        emptyIcon: Icons.receipt_long_outlined,
        itemBuilder: (context, order) => _OrderTile(order: order),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Order order;

  Color _color(AppColors colors) {
    switch (order.status) {
      case 'Approved':
        return colors.green;
      case 'Disapproved':
        return colors.red;
      default:
        return colors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final created = order.createdAt;
    final summary = order.items
        .map((i) => '${i.name} x${i.qty.round()}')
        .join(', ');

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.customer.isNotEmpty ? order.customer : order.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label: order.status, color: _color(context.appColors)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [order.name, if (created != null) formatDate(created)].join(' · '),
            style: muted,
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Text(
            formatRupees(order.total),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
