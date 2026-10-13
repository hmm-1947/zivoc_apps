class OrderItem {
  final String name;
  final double qty;
  final double amount;

  const OrderItem({required this.name, required this.qty, required this.amount});

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final name = (json['item_name'] as String?)?.trim() ?? '';
    final code = (json['item_code'] as String?)?.trim() ?? '';
    return OrderItem(
      name: name.isNotEmpty ? name : code,
      qty: (json['qty'] as num?)?.toDouble() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Order {
  final String name;
  final String customer;
  final String status;
  final double total;
  final DateTime? createdAt;
  final List<OrderItem> items;

  const Order({
    required this.name,
    required this.customer,
    required this.status,
    required this.total,
    required this.items,
    this.createdAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] as String?)?.trim() ?? '';
    final status = text('status');
    return Order(
      name: text('name'),
      customer: text('customer_name'),
      status: status.isEmpty ? 'Pending' : status,
      total: (json['grand_total'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(text('creation'))?.toLocal(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
