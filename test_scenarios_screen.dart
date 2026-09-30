// Project location: lib/features/test_organizer/test_scenarios_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/database.dart';

/// Scenario management for a single ACS/PTS standard. Opened from the
/// Test Organizer app bar once a standard is selected.
///
/// Hand-off to scheduling: active scenarios for a standard are offered in
/// the pending-session card (_PendingSessionTile in scheduling_screen.dart),
/// which passes the chosen id to SchedulingRepository.confirmSession() —
/// that is where test_sessions.scenario_id gets written.
class TestScenariosScreen extends ConsumerWidget {
  const TestScenariosScreen({
    super.key,
    required this.standardId,
    required this.standardLabel,
  });

  final int standardId;
  final String standardLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(testStandardsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Scenarios — $standardLabel')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Scenario'),
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _ScenarioFormDialog(standardId: standardId),
        ),
      ),
      body: StreamBuilder<List<TestScenario>>(
        stream: repo.watchAllScenariosForStandard(standardId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final scenarios = snapshot.data!;
          if (scenarios.isEmpty) {
            return _EmptyScenarios(standardId: standardId);
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final s in scenarios) _ScenarioTile(scenario: s),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyScenarios extends StatelessWidget {
  const _EmptyScenarios({required this.standardId});
  final int standardId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flight_takeoff_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No scenarios yet for this standard.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Scenarios added here can be attached to a session at '
              'confirmation time.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Scenario'),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _ScenarioFormDialog(standardId: standardId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioTile extends ConsumerWidget {
  const _ScenarioTile({required this.scenario});
  final TestScenario scenario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(testStandardsRepositoryProvider);
    final archived = !scenario.isActive;

    return Opacity(
      opacity: archived ? 0.5 : 1,
      child: ListTile(
        title: Text(scenario.scenarioTitle),
        subtitle: Text(
          archived
              ? 'Archived — ${scenario.scenarioNarrative}'
              : scenario.scenarioNarrative,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _ScenarioFormDialog(
            standardId: scenario.standardId,
            existing: scenario,
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          ),
          tooltip: archived ? 'Restore' : 'Archive',
          onPressed: () =>
              repo.setScenarioActive(scenario.id, archived),
        ),
      ),
    );
  }
}

/// Create when [existing] is null, edit otherwise.
class _ScenarioFormDialog extends ConsumerStatefulWidget {
  const _ScenarioFormDialog({required this.standardId, this.existing});
  final int standardId;
  final TestScenario? existing;

  @override
  ConsumerState<_ScenarioFormDialog> createState() =>
      _ScenarioFormDialogState();
}

class _ScenarioFormDialogState extends ConsumerState<_ScenarioFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController =
      TextEditingController(text: widget.existing?.scenarioTitle);
  late final _narrativeController =
      TextEditingController(text: widget.existing?.scenarioNarrative);
  late bool _isActive = widget.existing?.isActive ?? true;

  @override
  void dispose() {
    _titleController.dispose();
    _narrativeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(testStandardsRepositoryProvider);
    final title = _titleController.text.trim();
    final narrative = _narrativeController.text.trim();
    final existing = widget.existing;

    if (existing == null) {
      await repo.addScenario(
        standardId: widget.standardId,
        title: title,
        narrative: narrative,
        isActive: _isActive,
      );
    } else {
      await repo.updateScenario(
        existing.id,
        title: title,
        narrative: narrative,
        isActive: _isActive,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New Scenario' : 'Edit Scenario'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Scenario title'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _narrativeController,
                decoration: const InputDecoration(
                  labelText: 'Scenario narrative',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                minLines: 5,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Narrative is required'
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text(
                  'Only active scenarios are offered at session confirmation.',
                ),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
