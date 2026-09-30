import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/database.dart';
import '../../data/schema/location_services.dart';
import '../../data/schema/accounting.dart';

// Current-year IRS standard mileage rate — hardcoded here as a starting
// default; should move to a settings screen so it can be updated when
// the IRS publishes a new rate without a code change.
const double _currentIrsMileageRate = 0.67;

class MileageScreen extends ConsumerStatefulWidget {
  const MileageScreen({super.key});

  @override
  ConsumerState<MileageScreen> createState() => _MileageScreenState();
}

class _MileageScreenState extends ConsumerState<MileageScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mileage Tracker')),
      body: Row(
        children: [
          const Expanded(child: _NewMileageForm()),
          const VerticalDivider(width: 1),
          Expanded(child: _MileageLogList()),
        ],
      ),
    );
  }
}

class _NewMileageForm extends ConsumerStatefulWidget {
  const _NewMileageForm();

  @override
  ConsumerState<_NewMileageForm> createState() => _NewMileageFormState();
}

class _NewMileageFormState extends ConsumerState<_NewMileageForm> {
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  final _purposeController = TextEditingController();
  final _milesController = TextEditingController();

  LocationInputType _startType = LocationInputType.streetAddress;
  LocationInputType _endType = LocationInputType.streetAddress;
  DateTime _date = DateTime.now();

  bool _resolving = false;
  String? _resolutionMessage;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(mileageRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New Mileage Entry',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            _LocationField(
              label: 'Start location',
              controller: _startController,
              type: _startType,
              onTypeChanged: (t) => setState(() => _startType = t),
            ),
            const SizedBox(height: 12),
            _LocationField(
              label: 'End location',
              controller: _endController,
              type: _endType,
              onTypeChanged: (t) => setState(() => _endType = t),
            ),
            const SizedBox(height: 16),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_date.toString().split(' ').first),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            TextField(
              controller: _purposeController,
              decoration: const InputDecoration(labelText: 'Purpose (optional)'),
            ),
            const SizedBox(height: 12),

            OutlinedButton.icon(
              icon: _resolving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.route_outlined),
              label: const Text('Auto-Calculate Driving Distance'),
              onPressed: _resolving
                  ? null
                  : () async {
                      if (_startController.text.trim().isEmpty ||
                          _endController.text.trim().isEmpty) {
                        return;
                      }
                      setState(() {
                        _resolving = true;
                        _resolutionMessage = null;
                      });

                      final miles = await repo.attemptAutoCalculateMiles(
                        startLocation: _startController.text.trim(),
                        startType: _startType,
                        endLocation: _endController.text.trim(),
                        endType: _endType,
                      );

                      setState(() {
                        _resolving = false;
                        if (miles != null) {
                          _milesController.text = miles.toStringAsFixed(1);
                          _resolutionMessage =
                              'Resolved via routing — verify before saving.';
                        } else {
                          _resolutionMessage =
                              'Could not auto-resolve one or both locations '
                              '— enter miles manually below.';
                        }
                      });
                    },
            ),
            if (_resolutionMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _resolutionMessage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),

            TextField(
              controller: _milesController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Miles (auto-filled or entered manually)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rate applied: \$${_currentIrsMileageRate.toStringAsFixed(3)}/mi '
              '(current-year IRS standard mileage rate)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            FilledButton(
              onPressed: () async {
                final miles = double.tryParse(_milesController.text.trim());
                if (miles == null ||
                    _startController.text.trim().isEmpty ||
                    _endController.text.trim().isEmpty) {
                  return;
                }

                await repo.createMileageLog(
                  date: _date,
                  startLocation: _startController.text.trim(),
                  startType: _startType,
                  endLocation: _endController.text.trim(),
                  endType: _endType,
                  miles: miles,
                  distanceSource: _resolutionMessage?.startsWith('Resolved') == true
                      ? DistanceSource.geocodedRoute
                      : DistanceSource.manualEntry,
                  rateApplied: _currentIrsMileageRate,
                  purpose: _purposeController.text.trim().isEmpty
                      ? null
                      : _purposeController.text.trim(),
                );

                _startController.clear();
                _endController.clear();
                _purposeController.clear();
                _milesController.clear();
                setState(() => _resolutionMessage = null);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mileage entry saved.')),
                  );
                }
              },
              child: const Text('Save Mileage Entry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A location input paired with its type selector — the core UI piece
/// answering "street address, business name, or airport identifier."
class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.label,
    required this.controller,
    required this.type,
    required this.onTypeChanged,
  });

  final String label;
  final TextEditingController controller;
  final LocationInputType type;
  final ValueChanged<LocationInputType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: _hintFor(type),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        SegmentedButton<LocationInputType>(
          segments: const [
            ButtonSegment(
              value: LocationInputType.streetAddress,
              label: Text('Address'),
              icon: Icon(Icons.location_on_outlined, size: 16),
            ),
            ButtonSegment(
              value: LocationInputType.businessName,
              label: Text('Business'),
              icon: Icon(Icons.store_outlined, size: 16),
            ),
            ButtonSegment(
              value: LocationInputType.airportIdentifier,
              label: Text('Airport'),
              icon: Icon(Icons.flight_outlined, size: 16),
            ),
          ],
          selected: {type},
          onSelectionChanged: (selection) => onTypeChanged(selection.first),
        ),
      ],
    );
  }

  String _hintFor(LocationInputType type) {
    switch (type) {
      case LocationInputType.streetAddress:
        return 'e.g. 123 Main St, Springfield, IL';
      case LocationInputType.businessName:
        return 'e.g. Springfield Flight Academy';
      case LocationInputType.airportIdentifier:
        return 'e.g. KSPI, or the FAA LID';
    }
  }
}

class _MileageLogList extends ConsumerWidget {
  const _MileageLogList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mileageRepositoryProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mileage Log', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<MileageLog>>(
              stream: repo.watchAllMileageLogs(),
              builder: (context, snapshot) {
                final logs = snapshot.data ?? [];
                if (logs.isEmpty) {
                  return const Center(child: Text('No mileage entries yet.'));
                }
                return ListView(
                  children: [
                    for (final log in logs)
                      Card(
                        child: ListTile(
                          title: Text('${log.startLocation} → ${log.endLocation}'),
                          subtitle: Text(
                            '${log.date.toString().split(' ').first} · '
                            '${log.miles.toStringAsFixed(1)} mi · '
                            '${log.distanceSource == DistanceSource.geocodedRoute ? "Routed" : "Manual"}'
                            '${log.purpose != null ? " · ${log.purpose}" : ""}',
                          ),
                          trailing: Text(
                            '\$${log.computedDeduction.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium,
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
