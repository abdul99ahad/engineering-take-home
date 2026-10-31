import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';
import 'sharing_rules.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shares the diary with a doctor. Pops `true` once the share is created.
class ShareFormScreen extends StatefulWidget {
  const ShareFormScreen({super.key, required this.api, this.now = DateTime.now});

  final ApiClient api;

  /// Today's date comes from here, so tests can fix it.
  final DateTime Function() now;

  @override
  State<ShareFormScreen> createState() => _ShareFormScreenState();
}

class _ShareFormScreenState extends State<ShareFormScreen> {
  late final Future<List<Clinician>> _clinicians = widget.api.listClinicians();
  Clinician? _clinician;
  Period? _preset = Period.last7Days;
  late DateTimeRange _range = _presetRange(Period.last7Days);
  bool _includeNotes = false;
  bool _agreed = false;
  bool _saving = false;

  DateTimeRange _presetRange(Period period) {
    final range = periodRange(period, widget.now());
    return DateTimeRange(start: range.from, end: range.to);
  }

  /// Any change to what is shared asks for consent again: the patient agrees to exactly these
  /// data (O.Cons_1).
  void _change(VoidCallback update) => setState(() {
    update();
    _agreed = false;
  });

  Future<void> _chooseDates() async {
    final today = dayOf(widget.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      initialDateRange: _range,
      helpText: 'Which days to share',
      saveText: 'Use these days',
    );
    if (picked == null) return;
    _change(() {
      _preset = null;
      _range = picked;
    });
  }

  Future<void> _share() async {
    final clinician = _clinician!;
    setState(() => _saving = true);
    try {
      await widget.api.createShare(
        clinicianId: clinician.id,
        from: _range.start,
        to: _range.end,
        includeNotes: _includeNotes,
      );
      widget.api.track('share_created');
      if (mounted) Navigator.of(context).pop(true);
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't share your diary. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canShare = _clinician != null && _agreed && !_saving;
    return Scaffold(
      appBar: AppBar(title: const Text('Share your diary')),
      bottomNavigationBar: SafeArea(
        child: ContentColumn(
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: FilledButton(
              onPressed: canShare ? _share : null,
              child: const Text('Share my diary'),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your doctor', style: text.titleMedium),
                const SizedBox(height: Space.s),
                _DoctorPicker(
                  clinicians: _clinicians,
                  selected: _clinician,
                  onSelected: (clinician) => _change(() => _clinician = clinician),
                ),
                const SizedBox(height: Space.xl),
                Text('Which days', style: text.titleMedium),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.s,
                  children: [
                    for (final (period, label) in [
                      (Period.last7Days, 'Last 7 days'),
                      (Period.last30Days, 'Last 30 days'),
                    ])
                      FilterChip(
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        label: Text(label),
                        selected: _preset == period,
                        onSelected: (_) => _change(() {
                          _preset = period;
                          _range = _presetRange(period);
                        }),
                      ),
                    FilterChip(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      label: const Text('Choose dates'),
                      selected: _preset == null,
                      onSelected: (_) => _chooseDates(),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s),
                Text(formatDateRange(_range.start, _range.end), style: text.bodyMedium),
                const SizedBox(height: Space.xl),
                Text('Your notes', style: text.titleMedium),
                const SizedBox(height: Space.s),
                SwitchListTile(
                  title: const Text('Include my notes'),
                  subtitle: const Text('Off by default. Your doctor sees mood and symptoms.'),
                  value: _includeNotes,
                  onChanged: (on) => _change(() => _includeNotes = on),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: Space.xl),
                _ConsentPanel(
                  clinician: _clinician,
                  range: _range,
                  includeNotes: _includeNotes,
                  agreed: _agreed,
                  onAgreed: (agreed) => setState(() => _agreed = agreed),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorPicker extends StatelessWidget {
  const _DoctorPicker({required this.clinicians, required this.selected, required this.onSelected});

  final Future<List<Clinician>> clinicians;
  final Clinician? selected;
  final ValueChanged<Clinician> onSelected;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: clinicians,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            "Couldn't load your doctors. Go back and try again.",
            style: Theme.of(context).textTheme.bodyMedium,
          );
        }
        final list = snapshot.data;
        if (list == null) return const LinearProgressIndicator();
        return Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final clinician in list)
              FilterChip(
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(clinician.name),
                selected: selected?.id == clinician.id,
                onSelected: (_) => onSelected(clinician),
              ),
          ],
        );
      },
    );
  }
}

/// The terms the patient agrees to before anything is shared (O.Purp_1). Outlined in ink so it
/// reads as a document, not as another form section.
class _ConsentPanel extends StatelessWidget {
  const _ConsentPanel({
    required this.clinician,
    required this.range,
    required this.includeNotes,
    required this.agreed,
    required this.onAgreed,
  });

  final Clinician? clinician;
  final DateTimeRange range;
  final bool includeNotes;
  final bool agreed;
  final ValueChanged<bool> onAgreed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final clinician = this.clinician;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: 1.5),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.paper,
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: AppColors.ink),
                const SizedBox(width: Space.s),
                Text('Your consent', style: text.titleMedium),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: clinician == null
                ? Text("Choose your doctor to see what you're agreeing to.", style: text.bodyMedium)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, term) in consentTerms(
                        clinician: clinician,
                        from: range.start,
                        to: range.end,
                        includeNotes: includeNotes,
                      ).indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.s),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: Space.l,
                                child: Text('${i + 1}.', style: text.bodyLarge),
                              ),
                              Expanded(child: Text(term, style: text.bodyLarge)),
                            ],
                          ),
                        ),
                      Text('Version $consentVersion of these terms', style: text.labelMedium),
                    ],
                  ),
          ),
          if (clinician != null) ...[
            const Divider(height: 1, color: AppColors.line),
            CheckboxListTile(
              value: agreed,
              onChanged: (value) => onAgreed(value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('I agree to share my diary on these terms.', style: text.labelLarge),
            ),
          ],
        ],
      ),
    );
  }
}
