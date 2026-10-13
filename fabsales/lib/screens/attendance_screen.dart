import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/refreshable_list.dart';
import '../widgets/surface_card.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  AttendanceStatus? _status;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await AttendanceService.fetch(context.read<AuthService>());
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } on OrderException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _mark(String logType) async {
    setState(() => _busy = true);
    try {
      final status = await AttendanceService.mark(context.read<AuthService>(), logType);
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
      _toast(logType == 'IN' ? 'Marked in.' : 'Marked out.');
    } on OrderException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String get _statusText {
    final s = _status;
    if (s == null || s.status == null) return 'Not marked in today';
    if (s.isIn) return 'Marked in at ${s.lastTime}';
    return 'Marked out at ${s.lastTime}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final status = _status;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: status == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: MessageView(icon: Icons.event_busy_outlined, text: _error!, onRetry: _load),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  SurfaceCard(
                    child: Column(
                      children: [
                        Icon(Icons.calendar_today_outlined, color: theme.colorScheme.primary),
                        const SizedBox(height: 8),
                        Text(
                          formatLongDate(DateTime.now()),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusText,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: status.isIn ? colors.green : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (status.firstIn != null) ...[
                          const SizedBox(height: 4),
                          Text('First in: ${status.firstIn}', style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.green,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _busy || status.isIn ? null : () => _mark('IN'),
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('Mark In'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.red,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _busy || !status.isIn ? null : () => _mark('OUT'),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Mark Out'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
