import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lead.dart';
import '../services/data_store.dart';
import '../widgets/lead_tile.dart';
import '../widgets/refreshable_list.dart';

class LeadsScreen extends StatelessWidget {
  const LeadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<DataStore, (List<Lead>?, String?)>(
      selector: (_, store) => (store.leads, store.leadsError),
      builder: (context, data, _) => RefreshableList<Lead>(
        items: data.$1,
        error: data.$2,
        onRefresh: context.read<DataStore>().refresh,
        emptyText: 'No leads yet.',
        emptyIcon: Icons.people_alt_outlined,
        itemBuilder: (context, lead) => LeadTile(lead: lead),
      ),
    );
  }
}
