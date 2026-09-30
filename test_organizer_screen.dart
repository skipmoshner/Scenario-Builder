import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/schema/test_standards.dart';

class TestOrganizerScreen extends ConsumerStatefulWidget {
  const TestOrganizerScreen({super.key});

  @override
  ConsumerState<TestOrganizerScreen> createState() =>
      _TestOrganizerScreenState();
}

class _TestOrganizerScreenState extends ConsumerState<TestOrganizerScreen> {
  int? _selectedStandardId;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(testStandardsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Practical Test Organizer')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StreamBuilder<List<TestStandard>>(
            stream: repo.watchAllStandards(),
            builder: (context, snapshot) {
              final standards = snapshot.data ?? [];
              return Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'ACS / PTS Standard',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedStandardId,
                  items: [
                    for (final s in standards)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.certificateRating} '
                          '(${s.standardType.name.toUpperCase()})',
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _selectedStandardId = id),
                ),
              );
            },
          ),
          if (_selectedStandardId != null)
            Expanded(child: _AreasList(standardId: _selectedStandardId!)),
        ],
      ),
    );
  }
}

class _AreasList extends ConsumerWidget {
  const _AreasList({required this.standardId});
  final int standardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(testStandardsRepositoryProvider);
    return StreamBuilder<List<AreaOfOperation>>(
      stream: repo.watchAreasForStandard(standardId),
      builder: (context, snapshot) {
        final areas = snapshot.data ?? [];
        return ListView(
          children: [for (final area in areas) _AreaTile(area: area)],
        );
      },
    );
  }
}

class _AreaTile extends ConsumerWidget {
  const _AreaTile({required this.area});
  final AreaOfOperation area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(testStandardsRepositoryProvider);
    return ExpansionTile(
      title: Text('${area.areaCode} — ${area.areaTitle}'),
      subtitle: Row(
        children: [
          const Text('Random draw count: '),
          SizedBox(
            width: 60,
            child: TextFormField(
              initialValue: area.randomDrawCount.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true),
              onFieldSubmitted: (value) {
                final count = int.tryParse(value) ?? area.randomDrawCount;
                repo.updateRandomDrawCount(area.id, count);
              },
            ),
          ),
        ],
      ),
      children: [
        StreamBuilder<List<AcsTask>>(
          stream: repo.watchTasksForArea(area.id),
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? [];
            return Column(
              children: [for (final task in tasks) _TaskTile(task: task)],
            );
          },
        ),
      ],
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final AcsTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(testStandardsRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: ExpansionTile(
        title: Text('${task.taskCode} — ${task.taskTitle}'),
        children: [
          StreamBuilder<List<AcsElement>>(
            stream: repo.watchElementsForTask(task.id),
            builder: (context, snapshot) {
              final elements = snapshot.data ?? [];
              return Column(
                children: [
                  for (final element in elements)
                    _ElementRow(element: element),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ElementRow extends ConsumerWidget {
  const _ElementRow({required this.element});
  final AcsElement element;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(testStandardsRepositoryProvider);
    return ListTile(
      dense: true,
      title: Text('${element.elementKey} — ${element.elementDescription}'),
      subtitle: Text(element.elementType.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<InclusionMode>(
            value: element.inclusionMode,
            items: [
              for (final mode in InclusionMode.values)
                DropdownMenuItem(value: mode, child: Text(_label(mode))),
            ],
            onChanged: (mode) {
              if (mode != null) {
                repo.updateInclusionMode(element.id, mode);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.quiz_outlined),
            tooltip: 'Manage questions (up to 5)',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _QuestionManagerDialog(element: element),
            ),
          ),
        ],
      ),
    );
  }

  String _label(InclusionMode mode) {
    switch (mode) {
      case InclusionMode.alwaysInclude:
        return 'Always Include';
      case InclusionMode.randomInclude:
        return 'Random Include';
      case InclusionMode.akrDeficiency:
        return 'AKR Deficiency';
      case InclusionMode.includedDuringTest:
        return 'Included During Test';
    }
  }
}

class _QuestionManagerDialog extends ConsumerStatefulWidget {
  const _QuestionManagerDialog({required this.element});
  final AcsElement element;

  @override
  ConsumerState<_QuestionManagerDialog> createState() =>
      _QuestionManagerDialogState();
}

class _QuestionManagerDialogState
    extends ConsumerState<_QuestionManagerDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(testStandardsRepositoryProvider);
    return AlertDialog(
      title: Text('Questions — ${widget.element.elementKey}'),
      content: SizedBox(
        width: 400,
        child: StreamBuilder<List<ElementQuestion>>(
          stream: repo.watchQuestionsForElement(widget.element.id),
          builder: (context, snapshot) {
            final questions = snapshot.data ?? [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final q in questions)
                  ListTile(
                    dense: true,
                    title: Text('${q.sequence}. ${q.questionText}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => repo.deleteQuestion(q.id),
                    ),
                  ),
                if (questions.length < 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: 'New question',
                              errorText: _error,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            if (_controller.text.trim().isEmpty) return;
                            try {
                              await repo.addQuestion(
                                widget.element.id,
                                _controller.text.trim(),
                              );
                              _controller.clear();
                              setState(() => _error = null);
                            } on StateError catch (e) {
                              setState(() => _error = e.message);
                            }
                          },
                        ),
                      ],
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Maximum of 5 questions reached for this element.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
