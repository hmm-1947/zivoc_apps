import 'package:flutter/material.dart';

class RefreshableList<T> extends StatelessWidget {
  const RefreshableList({
    super.key,
    required this.items,
    required this.error,
    required this.onRefresh,
    required this.itemBuilder,
    required this.emptyText,
    required this.emptyIcon,
  });

  final List<T>? items;
  final String? error;
  final Future<void> Function() onRefresh;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final IconData emptyIcon;

  Widget _scrollable(Widget child) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list == null && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list == null) {
      return _scrollable(
        MessageView(icon: Icons.cloud_off_rounded, text: error!, onRetry: onRefresh),
      );
    }
    if (list.isEmpty) {
      return _scrollable(MessageView(icon: emptyIcon, text: emptyText));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => itemBuilder(context, list[i]),
      ),
    );
  }
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => onRetry!(), child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}
