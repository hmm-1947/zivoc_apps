import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/order_service.dart';
import 'initial_avatar.dart';

class LeadChoice {
  final Lead? lead;
  final NewLead? newLead;

  const LeadChoice.existing(Lead this.lead) : newLead = null;
  const LeadChoice.created(NewLead this.newLead) : lead = null;
}

class LeadPickerDialog extends StatefulWidget {
  const LeadPickerDialog({super.key, required this.leads});

  final List<Lead> leads;

  static Future<LeadChoice?> show(BuildContext context, List<Lead> leads) {
    return showDialog<LeadChoice>(
      context: context,
      builder: (_) => LeadPickerDialog(leads: leads),
    );
  }

  @override
  State<LeadPickerDialog> createState() => _LeadPickerDialogState();
}

class _LeadPickerDialogState extends State<LeadPickerDialog> {
  final _search = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _org = TextEditingController();
  final _job = TextEditingController();
  final _mobile = TextEditingController();

  bool _creating = false;
  String _query = '';

  @override
  void dispose() {
    for (final c in [_search, _first, _middle, _last, _org, _job, _mobile]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Lead> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.leads;
    return widget.leads
        .where(
          (l) =>
              l.displayName.toLowerCase().contains(q) ||
              l.companyName.toLowerCase().contains(q) ||
              l.phone.toLowerCase().contains(q) ||
              l.email.toLowerCase().contains(q) ||
              l.name.toLowerCase().contains(q),
        )
        .toList();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      LeadChoice.created(
        NewLead(
          firstName: _first.text.trim(),
          middleName: _middle.text.trim(),
          lastName: _last.text.trim(),
          organization: _org.text.trim(),
          jobTitle: _job.text.trim(),
          mobile: _mobile.text.trim(),
        ),
      ),
    );
  }

  String? _nameRule(String? _) {
    if (_first.text.trim().isEmpty && _org.text.trim().isEmpty) {
      return 'Enter a first name or an organization name';
    }
    return null;
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        textCapitalization: keyboard == null ? TextCapitalization.words : TextCapitalization.none,
        validator: validator,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _pickView() {
    final results = _filtered;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search leads',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: results.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No matching leads.')),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final lead = results[i];
                    final sub = lead.phone.isNotEmpty ? lead.phone : lead.companyName;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: InitialAvatar(text: lead.displayName, size: 38),
                      title: Text(lead.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop(LeadChoice.existing(lead)),
                    );
                  },
                ),
        ),
        const Divider(),
        TextButton.icon(
          onPressed: () => setState(() => _creating = true),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Create new lead'),
        ),
      ],
    );
  }

  Widget _formView() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_first, 'First name', validator: _nameRule),
            _field(_middle, 'Middle name'),
            _field(_last, 'Last name'),
            _field(_org, 'Organization name', validator: _nameRule),
            _field(_job, 'Job title'),
            _field(_mobile, 'Mobile number', keyboard: TextInputType.phone),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_creating ? 'New lead' : 'Select lead'),
      content: SizedBox(width: 400, child: _creating ? _formView() : _pickView()),
      actions: _creating
          ? [
              TextButton(onPressed: () => setState(() => _creating = false), child: const Text('Back')),
              FilledButton(onPressed: _submit, child: const Text('Create order')),
            ]
          : [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}
