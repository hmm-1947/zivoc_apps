import 'package:flutter/material.dart';

import '../widgets/refreshable_list.dart';

class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: MessageView(icon: icon, text: '$label coming soon.'));
  }
}
