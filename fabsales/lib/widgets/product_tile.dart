import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../utils/format.dart';
import 'initial_avatar.dart';
import 'surface_card.dart';

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Product product;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Widget _avatar(BuildContext context) {
    final fallback = InitialAvatar(text: product.displayName);
    if (product.image.isEmpty) return fallback;

    final url = product.image.startsWith('http') ? product.image : '${Env.baseUrl}${product.image}';
    final headers = context.read<AuthService>().authHeaders();

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.network(
        url,
        headers: headers,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final subtitle = [
      if (product.group.isNotEmpty) product.group,
      product.code,
    ].join(' · ');

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: [
          _avatar(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatRupees(product.rate),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (selecting) ...[
            const SizedBox(width: 4),
            Checkbox(value: selected, onChanged: (_) => onTap()),
          ],
        ],
      ),
    );
  }
}
