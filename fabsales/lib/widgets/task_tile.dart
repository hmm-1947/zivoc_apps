import 'package:flutter/material.dart';

import '../models/task.dart';
import '../utils/format.dart';
import 'initial_avatar.dart';
import 'surface_card.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.onTap});

  final Task task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final created = task.createdAt;

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          InitialAvatar(text: task.title),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (task.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(task.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                ],
                if (created != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('${formatDate(created)} · ${formatTime(created)}', style: muted),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
