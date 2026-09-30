import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/schema/contacts.dart';

class CrmScreen extends ConsumerStatefulWidget {
  const CrmScreen({super.key});

  @override
  ConsumerState<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends ConsumerState<CrmScreen> {
  int? _selectedContactId;
  LifecycleStage? _filterStage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Add contact',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const _AddContactDialog(),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _StageFilterBar(
                  selected: _filterStage,
                  onChanged: (s) => setState(() => _filterStage = s),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _ContactList(
                    filterStage: _filterStage,
                    selectedContactId: _selectedContactId,
                    onSelect: (id) => setState(() => _selectedContactId = id),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedContactId == null
                ? const Center(child: Text('Select a contact to view details.'))
                : _ContactDetail(contactId: _selectedContactId!),
          ),
          const VerticalDivider(width: 1),
          const SizedBox(width: 280, child: _ReferralRollupPanel()),
        ],
      ),
    );
  }
}

class _StageFilterBar extends StatelessWidget {
  const _StageFilterBar({required this.selected, required this.onChanged});
  final LifecycleStage? selected;
  final ValueChanged<LifecycleStage?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 6,
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final stage in LifecycleStage.values)
            ChoiceChip(
              label: Text(_stageLabel(stage)),
              selected: selected == stage,
              onSelected: (_) => onChanged(stage),
            ),
        ],
      ),
    );
  }
}

String _stageLabel(LifecycleStage stage) {
  switch (stage) {
    case LifecycleStage.lead:
      return 'Lead';
    case LifecycleStage.prospect:
      return 'Prospect';
    case LifecycleStage.applicant:
      return 'Applicant';
    case LifecycleStage.customerAlumni:
      return 'Alumni';
    case LifecycleStage.lost:
      return 'Lost';
  }
}

class _ContactList extends ConsumerWidget {
  const _ContactList({
    required this.filterStage,
    required this.selectedContactId,
    required this.onSelect,
  });

  final LifecycleStage? filterStage;
  final int? selectedContactId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(contactsRepositoryProvider);
    final stream = filterStage == null
        ? repo.watchAllContacts()
        : repo.watchContactsByStage(filterStage!);

    return StreamBuilder<List<Contact>>(
      stream: stream,
      builder: (context, snapshot) {
        final contacts = snapshot.data ?? [];
        if (contacts.isEmpty) {
          return const Center(child: Text('No contacts yet.'));
        }
        return ListView(
          children: [
            for (final c in contacts)
              ListTile(
                selected: c.id == selectedContactId,
                title: Text(c.fullName),
                subtitle: Text(_stageLabel(c.lifecycleStage)),
                onTap: () => onSelect(c.id),
              ),
          ],
        );
      },
    );
  }
}

class _AddContactDialog extends ConsumerStatefulWidget {
  const _AddContactDialog();

  @override
  ConsumerState<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends ConsumerState<_AddContactDialog> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  LeadSource _leadSource = LeadSource.other;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(contactsRepositoryProvider);
    return AlertDialog(
      title: const Text('Add Contact'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<LeadSource>(
            decoration: const InputDecoration(labelText: 'Lead source'),
            value: _leadSource,
            items: [
              for (final s in LeadSource.values)
                DropdownMenuItem(value: s, child: Text(s.name)),
            ],
            onChanged: (s) => setState(() => _leadSource = s!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (_nameController.text.trim().isEmpty) return;
            await repo.createContact(
              fullName: _nameController.text.trim(),
              email: _emailController.text.trim().isEmpty
                  ? null
                  : _emailController.text.trim(),
              phone: _phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text.trim(),
              leadSource: _leadSource,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ContactDetail extends ConsumerWidget {
  const _ContactDetail({required this.contactId});
  final int contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(contactsRepositoryProvider);

    return StreamBuilder<Contact?>(
      stream: repo.watchContact(contactId),
      builder: (context, snapshot) {
        final contact = snapshot.data;
        if (contact == null) return const SizedBox.shrink();

        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(child: Text(contact.fullName[0])),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(contact.fullName,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(_stageLabel(contact.lifecycleStage)),
                      ],
                    ),
                    const Spacer(),
                    DropdownButton<LifecycleStage>(
                      value: contact.lifecycleStage,
                      items: [
                        for (final s in LifecycleStage.values)
                          DropdownMenuItem(value: s, child: Text(_stageLabel(s))),
                      ],
                      onChanged: (s) {
                        if (s != null) repo.updateLifecycleStage(contact.id, s);
                      },
                    ),
                  ],
                ),
              ),
              const TabBar(tabs: [
                Tab(text: 'Activities'),
                Tab(text: 'Opportunities'),
                Tab(text: 'Certificates'),
                Tab(text: 'CE Tracking'),
              ]),
              Expanded(
                child: TabBarView(
                  children: [
                    _ActivitiesTab(contactId: contact.id),
                    _OpportunitiesTab(contactId: contact.id),
                    _CertificatesTab(contactId: contact.id),
                    _CeTrackingTab(contactId: contact.id),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActivitiesTab extends ConsumerWidget {
  const _ActivitiesTab({required this.contactId});
  final int contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(contactsRepositoryProvider);
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ContactActivity>>(
            stream: repo.watchActivitiesForContact(contactId),
            builder: (context, snapshot) {
              final activities = snapshot.data ?? [];
              return ListView(
                children: [
                  for (final a in activities)
                    ListTile(
                      leading: Icon(_activityIcon(a.activityType)),
                      title: Text(a.notes ?? a.activityType.name),
                      subtitle: Text(a.activityDate.toString()),
                    ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Log Activity'),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _LogActivityDialog(contactId: contactId),
            ),
          ),
        ),
      ],
    );
  }

  IconData _activityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.call:
        return Icons.call;
      case ActivityType.email:
        return Icons.email;
      case ActivityType.meeting:
        return Icons.people;
      case ActivityType.note:
        return Icons.note;
    }
  }
}

class _LogActivityDialog extends ConsumerStatefulWidget {
  const _LogActivityDialog({required this.contactId});
  final int contactId;

  @override
  ConsumerState<_LogActivityDialog> createState() => _LogActivityDialogState();
}

class _LogActivityDialogState extends ConsumerState<_LogActivityDialog> {
  ActivityType _type = ActivityType.note;
  final _notesController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(contactsRepositoryProvider);
    return AlertDialog(
      title: const Text('Log Activity'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<ActivityType>(
            value: _type,
            items: [
              for (final t in ActivityType.values)
                DropdownMenuItem(value: t, child: Text(t.name)),
            ],
            onChanged: (t) => setState(() => _type = t!),
          ),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await repo.addActivity(
              contactId: widget.contactId,
              type: _type,
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _OpportunitiesTab extends ConsumerWidget {
  const _OpportunitiesTab({required this.contactId});
  final int contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(contactsRepositoryProvider);
    return StreamBuilder<List<Opportunity>>(
      stream: repo.watchOpportunitiesForContact(contactId),
      builder: (context, snapshot) {
        final opportunities = snapshot.data ?? [];
        return ListView(
          children: [
            for (final o in opportunities)
              ListTile(
                title: Text(o.opportunityType.name),
                subtitle: Text('Stage: ${o.stage.name}'
                    '${o.estimatedValue != null ? " · \$${o.estimatedValue!.toStringAsFixed(0)}" : ""}'),
                trailing: DropdownButton<OpportunityStage>(
                  value: o.stage,
                  items: [
                    for (final s in OpportunityStage.values)
                      DropdownMenuItem(value: s, child: Text(s.name)),
                  ],
                  onChanged: (s) {
                    if (s != null) repo.updateOpportunityStage(o.id, s);
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Opportunity'),
                onPressed: () async {
                  await repo.addOpportunity(
                    contactId: contactId,
                    type: OpportunityType.additionalRating,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CertificatesTab extends ConsumerWidget {
  const _CertificatesTab({required this.contactId});
  final int contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(contactsRepositoryProvider);
    return StreamBuilder<List<CertificateHeld>>(
      stream: repo.watchCertificatesForContact(contactId),
      builder: (context, snapshot) {
        final certs = snapshot.data ?? [];
        if (certs.isEmpty) {
          return const Center(
            child: Text('No certificates yet — these auto-populate when a '
                'test session is marked completed in Scheduling.'),
          );
        }
        return ListView(
          children: [
            for (final c in certs)
              ListTile(
                title: Text(c.certificateRating),
                subtitle: Text('Issued ${c.issueDate.toString().split(' ').first}'),
              ),
          ],
        );
      },
    );
  }
}

class _CeTrackingTab extends ConsumerWidget {
  const _CeTrackingTab({required this.contactId});
  final int contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(contactsRepositoryProvider);
    return StreamBuilder<List<ContinuingEducationRecord>>(
      stream: repo.watchCeTrackingForContact(contactId),
      builder: (context, snapshot) {
        final records = snapshot.data ?? [];
        if (records.isEmpty) {
          return const Center(child: Text('No CE tracking records yet.'));
        }
        return ListView(
          children: [
            for (final r in records)
              ListTile(
                title: Text(r.requirementType.name),
                subtitle: Text('Due ${r.dueDate.toString().split(' ').first} '
                    '· ${r.status.name}'),
                trailing: r.status == CeStatus.completed
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : TextButton(
                        onPressed: () =>
                            repo.markCeCompleted(r.id, DateTime.now()),
                        child: const Text('Mark Complete'),
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _ReferralRollupPanel extends ConsumerWidget {
  const _ReferralRollupPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(contactsRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Top Referrers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<Map<Contact, int>>(
              stream: repo.watchReferralRollup(),
              builder: (context, snapshot) {
                final rollup = snapshot.data ?? {};
                if (rollup.isEmpty) {
                  return const Text(
                    'No referral relationships yet. These populate when a '
                    'contact is created via third-party scheduling in the '
                    'Scheduling tab.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  );
                }
                final sorted = rollup.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                return ListView(
                  children: [
                    for (final entry in sorted)
                      ListTile(
                        dense: true,
                        title: Text(entry.key.fullName),
                        trailing: Text('${entry.value}'),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
