import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../services/data_store.dart';
import '../widgets/refreshable_list.dart';
import '../widgets/task_tile.dart';
import 'task_detail_screen.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: Selector<DataStore, (List<Task>?, String?)>(
        selector: (_, store) => (store.tasks, store.tasksError),
        builder: (context, data, _) => RefreshableList<Task>(
          items: data.$1,
          error: data.$2,
          onRefresh: context.read<DataStore>().refresh,
          emptyText: 'No tasks assigned yet.',
          emptyIcon: Icons.inbox_rounded,
          itemBuilder: (context, task) => TaskTile(
            task: task,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
            ),
          ),
        ),
      ),
    );
  }
}
