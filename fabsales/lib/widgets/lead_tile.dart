import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'initial_avatar.dart';
import 'status_chip.dart';
import 'surface_card.dart';

class LeadTile extends StatelessWidget {
  const LeadTile({super.key, required this.lead});

  final Lead lead;

  String get _subtitle {
    if (lead.companyName.isNotEmpty && lead.companyName != lead.displayName) return lead.companyName;
    if (lead.email.isNotEmpty) return lead.email;
    if (lead.phone.isNotEmpty) return lead.phone;
    return lead.name;
  }

  Color _statusColor(AppColors colors) {
    final value = lead.status.toLowerCase();
    if (value.contains('lost') || value.contains('not')) return colors.red;
    if (value.contains('contact') || value.contains('replied')) return colors.purple;
    if (value.contains('open') || value.contains('new') || value == 'lead') return colors.green;
    if (value.contains('interest') || value.contains('quot') || value.contains('convert')) {
      return colors.amber;
    }
    return colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final created = lead.createdAt;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          InitialAvatar(text: lead.displayName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(_subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (lead.status.isNotEmpty)
                StatusChip(label: lead.status, color: _statusColor(context.appColors)),
              if (created != null) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(formatDate(created), style: muted),
                  ],
                ),
              ],
            ],
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
