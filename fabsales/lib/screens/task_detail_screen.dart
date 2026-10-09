import 'package:flutter/material.dart';

import '../models/task.dart';
import 'drawing_screen.dart';

class TaskDetailScreen extends StatelessWidget {
  final Task task;

  const TaskDetailScreen({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = task.description.trim();

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Task'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      description.isEmpty ? 'No description provided.' : description,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.5,
                        color: description.isEmpty ? Colors.grey : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  icon: const Icon(Icons.draw_rounded),
                  label: const Text('Open drawing'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DrawingScreen()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
