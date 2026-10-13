class Product {
  final String code;
  final String name;
  final String group;
  final String image;
  final double rate;
  final String uom;

  const Product({
    required this.code,
    required this.name,
    required this.group,
    required this.image,
    required this.rate,
    required this.uom,
  });

  String get displayName => name.isNotEmpty ? name : code;

  factory Product.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] as String?)?.trim() ?? '';
    return Product(
      code: text('item_code').isNotEmpty ? text('item_code') : text('name'),
      name: text('item_name'),
      group: text('item_group'),
      image: text('image'),
      rate: (json['standard_rate'] as num?)?.toDouble() ?? 0,
      uom: text('stock_uom'),
    );
  }
}
