import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lead.dart';
import '../models/task.dart';
import '../services/auth_service.dart';
import '../services/data_store.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/initial_avatar.dart';
import '../widgets/lead_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/surface_card.dart';
import '../widgets/task_tile.dart';
import 'task_detail_screen.dart';
import 'tasks_screen.dart';

const _salesTarget = 0.0;
const _salesAchieved = 0.0;

void _comingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Coming soon')));
}

void _openTasks(BuildContext context) {
  final store = context.read<DataStore>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<DataStore>.value(
        value: store,
        child: const TasksScreen(),
      ),
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenLeads});

  final VoidCallback onOpenLeads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
            theme.scaffoldBackgroundColor,
          ],
          stops: const [0, 0.4],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: context.read<DataStore>().refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const _TopBar(),
              const SizedBox(height: 16),
              const _Greeting(),
              const SizedBox(height: 16),
              const _SummaryCard(),
              const SizedBox(height: 20),
              const _QuickActions(),
              const SizedBox(height: 12),
              const _MyTasks(),
              const SizedBox(height: 12),
              _RecentLeads(onViewAll: onOpenLeads),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final name = context.select<AuthService, String?>((a) => a.fullName) ?? '';

    return Row(
      children: [
        const _ZivocLogo(),
        const Spacer(),
        _CircleButton(icon: Icons.search_rounded, onTap: () => _comingSoon(context)),
        const SizedBox(width: 10),
        _CircleButton(
          icon: Icons.notifications_none_rounded,
          showDot: true,
          onTap: () => _comingSoon(context),
        ),
        const SizedBox(width: 10),
        InitialAvatar(text: name, size: 48),
      ],
    );
  }
}

class _ZivocLogo extends StatelessWidget {
  const _ZivocLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(size: const Size(30, 24), painter: _SlashPainter(context.appColors.orange)),
        const SizedBox(width: 8),
        Text(
          'ZIVOC',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _SlashPainter extends CustomPainter {
  const _SlashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final dx = i * 9.0 + 3;
      canvas.drawLine(Offset(dx, size.height - 2), Offset(dx + 8, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_SlashPainter oldDelegate) => oldDelegate.color != color;
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap, this.showDot = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: scheme.onSurface),
              if (showDot)
                Positioned(
                  top: 12,
                  right: 13,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: context.appColors.orange, shape: BoxShape.circle),
                    child: const SizedBox(width: 9, height: 9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (context.select<AuthService, String?>((a) => a.fullName) ?? '').trim();
    final first = name.isEmpty ? 'there' : name.split(RegExp(r'\s+')).first;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, $first 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                "Let's make today productive",
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SurfaceCard(
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                formatLongDate(DateTime.now()),
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final green = context.appColors.green;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final ratio = _salesTarget == 0 ? 0.0 : (_salesAchieved / _salesTarget).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Sales Target",
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatRupees(_salesTarget),
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRupees(_salesAchieved),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Achieved ($percent%)',
                    style: theme.textTheme.labelMedium?.copyWith(color: green),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 52,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: green.withValues(alpha: 0.12)),
                  child: Icon(Icons.bar_chart_rounded, color: green, size: 28),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 10,
                color: green,
                backgroundColor: green.withValues(alpha: 0.15),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          Selector<DataStore, (List<Lead>?, List<Task>?)>(
            selector: (_, store) => (store.leads, store.tasks),
            builder: (context, data, _) {
              final now = DateTime.now();
              final leads = data.$1;
              final tasks = data.$2;
              final newLeads = leads
                  ?.where((l) => l.createdAt != null && isSameDay(l.createdAt!, now))
                  .length;

              return Row(
                children: [
                  _Stat(value: newLeads?.toString() ?? '–', label: 'New Leads', muted: muted),
                  const _StatDivider(),
                  _Stat(value: tasks?.length.toString() ?? '–', label: 'Tasks', muted: muted),
                  const _StatDivider(),
                  _Stat(value: '0', label: 'Quotations', muted: muted),
                  const _StatDivider(),
                  _Stat(value: '0', label: 'Orders', muted: muted),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.muted});

  final String value;
  final String label;
  final TextStyle? muted;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: VerticalDivider(
        width: 1,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final actions = [
      (Icons.add_rounded, 'Add New\nLead', colors.orange, () => _comingSoon(context)),
      (Icons.call_rounded, 'Call\nReminders', colors.purple, () => _openTasks(context)),
      (Icons.description_rounded, 'Create\nQuotation', colors.blue, () => _comingSoon(context)),
      (Icons.location_on_rounded, 'Client\nCheck-in', colors.green, () => _comingSoon(context)),
    ];

    return Column(
      children: [
        const SectionHeader(title: 'Quick Actions'),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: actions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final action = actions[i];
              return _ActionTile(icon: action.$1, label: action.$2, color: action.$3, onTap: action.$4);
            },
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 108,
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: theme.colorScheme.onPrimary, size: 24),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MyTasks extends StatelessWidget {
  const _MyTasks();

  @override
  Widget build(BuildContext context) {
    return Selector<DataStore, (List<Task>?, String?)>(
      selector: (_, store) => (store.tasks, store.tasksError),
      builder: (context, data, _) {
        final items = data.$1;
        return Column(
          children: [
            SectionHeader(
              title: 'My Tasks',
              count: items?.length,
              onViewAll: () => _openTasks(context),
            ),
            _PreviewList<Task>(
              items: items,
              error: data.$2,
              emptyText: 'No tasks assigned yet.',
              itemBuilder: (task) => TaskTile(
                task: task,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentLeads extends StatelessWidget {
  const _RecentLeads({required this.onViewAll});

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Selector<DataStore, (List<Lead>?, String?)>(
      selector: (_, store) => (store.leads, store.leadsError),
      builder: (context, data, _) => Column(
        children: [
          SectionHeader(title: 'Recent Leads', onViewAll: onViewAll),
          _PreviewList<Lead>(
            items: data.$1,
            error: data.$2,
            emptyText: 'No leads yet.',
            itemBuilder: (lead) => LeadTile(lead: lead),
          ),
        ],
      ),
    );
  }
}

class _PreviewList<T> extends StatelessWidget {
  const _PreviewList({
    required this.items,
    required this.error,
    required this.emptyText,
    required this.itemBuilder,
  });

  final List<T>? items;
  final String? error;
  final String emptyText;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final list = items;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    if (list == null) {
      return SizedBox(
        height: 72,
        child: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Text(error!, textAlign: TextAlign.center, style: TextStyle(color: muted)),
        ),
      );
    }
    if (list.isEmpty) {
      return SizedBox(
        height: 72,
        child: Center(child: Text(emptyText, style: TextStyle(color: muted))),
      );
    }

    final shown = list.take(3).toList();
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          itemBuilder(shown[i]),
        ],
      ],
    );
  }
}
