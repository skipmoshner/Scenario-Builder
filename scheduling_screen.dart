import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/schema/contacts.dart';
import '../../data/schema/test_standards.dart';
import '../../data/schema/scheduling.dart';
import '../../data/repositories/test_standards_repository.dart';
import '../../data/repositories/scheduling_repository.dart';

class SchedulingScreen extends ConsumerStatefulWidget {
  const SchedulingScreen({super.key});

  @override
  ConsumerState<SchedulingScreen> createState() => _SchedulingScreenState();
}

class _SchedulingScreenState extends ConsumerState<SchedulingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduling')),
      body: Row(
        children: [
          Expanded(child: _NewSessionForm()),
          const VerticalDivider(width: 1),
          const Expanded(child: _PendingSessionsList()),
          const VerticalDivider(width: 1),
          const Expanded(child: _ConfirmedSessionsList()),
        ],
      ),
    );
  }
}

/// Session creation form — this is where the dual-path scheduling model
/// (self vs. any configurable scheduler role) is expressed directly in
/// the UI, per the architecture doc Section 4.
class _NewSessionForm extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NewSessionForm> createState() => _NewSessionFormState();
}

class _NewSessionFormState extends ConsumerState<_NewSessionForm> {
  int? _applicantContactId;
  int? _standardId;
  DateTime _sessionDate = DateTime.now().add(const Duration(days: 7));

  bool _selfScheduled = true;
  int? _schedulerContactId;
  int? _schedulerRoleId;
  int? _selfRoleId; // the system-default "Applicant (Self)" role id

  @override
  Widget build(BuildContext context) {
    final contactsRepo = ref.watch(contactsRepositoryProvider);
    final standardsRepo = ref.watch(testStandardsRepositoryProvider);
    final schedulingRepo = ref.watch(schedulingRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New Test Session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            StreamBuilder<List<Contact>>(
              stream: contactsRepo.watchAllContacts(),
              builder: (context, snapshot) {
                final contacts = snapshot.data ?? [];
                return DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Applicant',
                    border: OutlineInputBorder(),
                  ),
                  value: _applicantContactId,
                  items: [
                    for (final c in contacts)
                      DropdownMenuItem(value: c.id, child: Text(c.fullName)),
                  ],
                  onChanged: (id) => setState(() => _applicantContactId = id),
                );
              },
            ),
            const SizedBox(height: 12),

            StreamBuilder<List<TestStandard>>(
              stream: standardsRepo.watchAllStandards(),
              builder: (context, snapshot) {
                final standards = snapshot.data ?? [];
                return DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Standard (Certificate/Rating)',
                    border: OutlineInputBorder(),
                  ),
                  value: _standardId,
                  items: [
                    for (final s in standards)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(s.certificateRating),
                      ),
                  ],
                  onChanged: (id) => setState(() => _standardId = id),
                );
              },
            ),
            const SizedBox(height: 16),

            // --- Dual-path scheduling ---
            StreamBuilder<List<SchedulerRole>>(
              stream: contactsRepo.watchActiveSchedulerRoles(),
              builder: (context, snapshot) {
                final roles = snapshot.data ?? [];
                SchedulerRole? selfRole;
                for (final r in roles) {
                  if (r.isSystemDefault) {
                    selfRole = r;
                    break;
                  }
                }
                _selfRoleId ??= selfRole?.id;
                final thirdPartyRoles =
                    roles.where((r) => !r.isSystemDefault).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Who is scheduling?',
                        style: Theme.of(context).textTheme.titleMedium),
                    RadioListTile<bool>(
                      dense: true,
                      title: const Text('Applicant (Self)'),
                      value: true,
                      groupValue: _selfScheduled,
                      onChanged: (v) => setState(() => _selfScheduled = v!),
                    ),
                    RadioListTile<bool>(
                      dense: true,
                      title: const Text('Third-party scheduler'),
                      value: false,
                      groupValue: _selfScheduled,
                      onChanged: (v) => setState(() => _selfScheduled = v!),
                    ),
                    if (!_selfScheduled) ...[
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Scheduler role',
                          border: OutlineInputBorder(),
                        ),
                        value: _schedulerRoleId,
                        items: [
                          for (final r in thirdPartyRoles)
                            DropdownMenuItem(
                              value: r.id,
                              child: Text(r.roleName),
                            ),
                        ],
                        onChanged: (id) =>
                            setState(() => _schedulerRoleId = id),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<List<Contact>>(
                        stream: contactsRepo.watchAllContacts(),
                        builder: (context, snapshot) {
                          final contacts = snapshot.data ?? [];
                          return DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              labelText: 'Scheduler contact',
                              border: OutlineInputBorder(),
                            ),
                            value: _schedulerContactId,
                            items: [
                              for (final c in contacts)
                                DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.fullName),
                                ),
                            ],
                            onChanged: (id) =>
                                setState(() => _schedulerContactId = id),
                          );
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Session date'),
              subtitle: Text(_sessionDate.toString().split(' ').first),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _sessionDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _sessionDate = picked);
              },
            ),
            const SizedBox(height: 16),

            FilledButton(
              onPressed: _canSubmit()
                  ? () async {
                      final initiatedByContactId = _selfScheduled
                          ? _applicantContactId!
                          : _schedulerContactId!;
                      final initiatedByRoleId =
                          _selfScheduled ? _selfRoleId! : _schedulerRoleId!;

                      await schedulingRepo.createSession(
                        contactId: _applicantContactId!,
                        standardId: _standardId!,
                        initiatedByContactId: initiatedByContactId,
                        initiatedByRoleId: initiatedByRoleId,
                        sessionDate: _sessionDate,
                      );

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Session created — pending confirmation.')),
                        );
                      }
                    }
                  : null,
              child: const Text('Create Session'),
            ),
          ],
        ),
      ),
    );
  }

  bool _canSubmit() {
    if (_applicantContactId == null || _standardId == null) return false;
    if (_selfScheduled) return _selfRoleId != null;
    return _schedulerContactId != null && _schedulerRoleId != null;
  }
}

/// Lists sessions awaiting confirmation, with a confirm action that
/// triggers the resolution algorithm and displays the resolved elements.
class _PendingSessionsList extends ConsumerWidget {
  const _PendingSessionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulingRepo = ref.watch(schedulingRepositoryProvider);
    final standardsRepo = ref.watch(testStandardsRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pending Confirmation',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<TestSession>>(
              stream: schedulingRepo.watchPendingSessions(),
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? [];
                if (sessions.isEmpty) {
                  return const Center(child: Text('No sessions pending confirmation.'));
                }
                return ListView(
                  children: [
                    for (final session in sessions)
                      _PendingSessionTile(
                        session: session,
                        standardsRepo: standardsRepo,
                        schedulingRepo: schedulingRepo,
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

class _PendingSessionTile extends StatefulWidget {
  const _PendingSessionTile({
    required this.session,
    required this.standardsRepo,
    required this.schedulingRepo,
  });

  final TestSession session;
  final TestStandardsRepository standardsRepo;
  final SchedulingRepository schedulingRepo;

  @override
  State<_PendingSessionTile> createState() => _PendingSessionTileState();
}

class _PendingSessionTileState extends State<_PendingSessionTile> {
  int? _scenarioId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('Session #${widget.session.id} — '
            '${widget.session.sessionDate.toString().split(' ').first}'),
        subtitle: Text('Status: ${widget.session.status.name}'),
        children: [
          // Scenario hand-off point: scenarios managed in TestScenariosScreen
          // (features/test_organizer) are picked here and written to
          // test_sessions.scenario_id by confirmSession() below.
          StreamBuilder<List<TestScenario>>(
            stream: widget.standardsRepo
                .watchScenariosForStandard(widget.session.standardId),
            builder: (context, snapshot) {
              final scenarios = snapshot.data ?? [];
              // A selected scenario can be archived from the Test Organizer
              // while this card is open. DropdownButtonFormField asserts if
              // its value isn't among the items, so drop the stale selection
              // (after this frame) rather than confirming an archived one.
              final selectionValid = _scenarioId == null ||
                  scenarios.any((s) => s.id == _scenarioId);
              if (snapshot.hasData && !selectionValid) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _scenarioId = null);
                });
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                    labelText: 'Scenario (optional)',
                    helperText: snapshot.hasData && scenarios.isEmpty
                        ? 'No active scenarios for this standard — add them '
                            'in Test Organizer → Scenarios.'
                        : null,
                  ),
                  value: selectionValid ? _scenarioId : null,
                  items: [
                    for (final s in scenarios)
                      DropdownMenuItem(value: s.id, child: Text(s.scenarioTitle)),
                  ],
                  onChanged: (id) => setState(() => _scenarioId = id),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirm Session'),
              onPressed: () async {
                await widget.schedulingRepo.confirmSession(
                  widget.session.id,
                  scenarioId: _scenarioId,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Session confirmed — elements resolved (always / random-draw / AKR deficiency).',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists confirmed sessions and offers the "mark completed" action that
/// closes the loop into the CRM lifecycle (Section 3): writes a
/// certificates_held record, auto-generates the 24-month flight-review
/// CE tracking row, and flips the contact to customer_alumni.
class _ConfirmedSessionsList extends ConsumerWidget {
  const _ConfirmedSessionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulingRepo = ref.watch(schedulingRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Confirmed — Ready to Complete',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<TestSession>>(
              stream: schedulingRepo.watchConfirmedSessions(),
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? [];
                if (sessions.isEmpty) {
                  return const Center(child: Text('No confirmed sessions awaiting completion.'));
                }
                return ListView(
                  children: [
                    for (final session in sessions)
                      Card(
                        child: ListTile(
                          title: Text('Session #${session.id} — '
                              '${session.sessionDate.toString().split(' ').first}'),
                          trailing: FilledButton(
                            child: const Text('Mark Completed'),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => _CompleteSessionDialog(
                                sessionId: session.id,
                                schedulingRepo: schedulingRepo,
                              ),
                            ),
                          ),
                        ),
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

class _CompleteSessionDialog extends StatefulWidget {
  const _CompleteSessionDialog({
    required this.sessionId,
    required this.schedulingRepo,
  });

  final int sessionId;
  final SchedulingRepository schedulingRepo;

  @override
  State<_CompleteSessionDialog> createState() => _CompleteSessionDialogState();
}

class _CompleteSessionDialogState extends State<_CompleteSessionDialog> {
  final _ratingController = TextEditingController();
  final _certNumberController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Complete Session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ratingController,
            decoration: const InputDecoration(
              labelText: 'Certificate/rating earned',
              hintText: 'e.g. Private Pilot – Airplane',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _certNumberController,
            decoration: const InputDecoration(
              labelText: 'Certificate number (optional, PII — encrypted at rest)',
            ),
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
            if (_ratingController.text.trim().isEmpty) return;
            await widget.schedulingRepo.completeSession(
              widget.sessionId,
              certificateRating: _ratingController.text.trim(),
              certificateNumber: _certNumberController.text.trim().isEmpty
                  ? null
                  : _certNumberController.text.trim(),
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Complete & Update CRM'),
        ),
      ],
    );
  }
}
