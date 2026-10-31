import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';
import 'share_form_screen.dart';
import 'theme.dart';
import 'widgets.dart';

typedef _SharingData = ({
  List<Share> shares,
  List<AccessRecord> visits,
  Map<int, Clinician> clinicians,
  Map<int, DiaryEntry> entries,
});

/// Who the diary is shared with, stopping a share, and every time a doctor opened it.
class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  late Future<_SharingData> _data = _load();

  @override
  void initState() {
    super.initState();
    widget.api.track('sharing_opened');
  }

  Future<_SharingData> _load() async {
    final api = widget.api;
    final (shares, visits, clinicians, entries) = await (
      api.listShares(),
      api.listAccessLog(),
      api.listClinicians(),
      api.listEntries(),
    ).wait;
    return (
      shares: shares,
      visits: visits,
      clinicians: {for (final c in clinicians) c.id: c},
      entries: {for (final e in entries) e.id!: e},
    );
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _share() async {
    final shared = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => ShareFormScreen(api: widget.api)));
    if (shared == true) _reload();
  }

  Future<void> _stop(Share share, String doctor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop sharing with $doctor?'),
        content: const Text("Your doctor won't be able to open your diary any more."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep sharing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop sharing'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.revokeShare(share.id);
      widget.api.track('share_revoked');
      _reload();
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't stop sharing. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _share,
        icon: const Icon(Icons.share_outlined),
        label: const Text('Share diary'),
      ),
      body: FutureBuilder(
        future: _data,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 96),
            children: [
              ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sharing', style: text.headlineMedium),
                    const SizedBox(height: Space.xs),
                    Text("Doctors you've shared your diary with.", style: text.bodyMedium),
                    const SizedBox(height: Space.l),
                    if (snapshot.hasError)
                      _Notice(
                        "Couldn't load your sharing. Try again.",
                        action: TextButton(onPressed: _reload, child: const Text('Try again')),
                      )
                    else if (data == null)
                      const Center(child: CircularProgressIndicator())
                    else
                      ..._sections(context, data),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _sections(BuildContext context, _SharingData data) {
    String doctor(int id) => data.clinicians[id]?.name ?? 'Your doctor';
    final active = data.shares.where((s) => s.isActive).toList();
    final stopped = data.shares.where((s) => !s.isActive).toList();
    return [
      if (data.shares.isEmpty)
        const _Notice(
          "You haven't shared your diary yet. Share it with your doctor before your next "
          'appointment.',
        ),
      if (active.isNotEmpty) ...[
        const _Heading('Shared now'),
        for (final share in active)
          _ShareCard(
            doctor: doctor(share.clinicianId),
            details: _shareDetails(share),
            onStop: () => _stop(share, doctor(share.clinicianId)),
          ),
        const SizedBox(height: Space.xl),
      ],
      if (stopped.isNotEmpty) ...[
        const _Heading('Stopped'),
        for (final share in stopped)
          _ShareCard(
            doctor: doctor(share.clinicianId),
            details: '${_shareDetails(share)} · stopped ${formatShortDateTime(share.revokedAt!)}',
          ),
        const SizedBox(height: Space.xl),
      ],
      const _Heading("Your diary's visitors"),
      if (data.visits.isEmpty)
        const _Notice('No doctor has opened your diary yet.')
      else
        for (final visit in data.visits)
          _VisitCard(
            visit: visit,
            practice: data.clinicians[visit.clinicianId]?.practice,
            entries: data.entries,
          ),
    ];
  }

  String _shareDetails(Share share) =>
      '${formatDateRange(share.fromDate, share.toDate)} · '
      '${share.includeNotes ? 'mood, symptoms and notes' : 'mood and symptoms'}';
}

String _entries(int count) => count == 1 ? '1 entry' : '$count entries';

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ?action,
      ],
    ),
  );
}

/// A white card like EntryCard, without the mood rail (DESIGN.md: lists of people or records).
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    clipBehavior: Clip.antiAlias,
    decoration: const BoxDecoration(color: AppColors.surface, borderRadius: Radii.card),
    child: child,
  );
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.doctor, required this.details, this.onStop});

  final String doctor;
  final String details;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doctor, style: text.labelLarge),
            const SizedBox(height: Space.xs),
            Text(details, style: text.labelMedium),
            if (onStop != null) ...[
              const SizedBox(height: Space.s),
              TextButton(
                onPressed: onStop,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('Stop sharing'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One time a doctor opened the diary. Expands to show the entries they saw.
class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit, required this.practice, required this.entries});

  final AccessRecord visit;
  final String? practice;
  final Map<int, DiaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final seen = [for (final id in visit.entryIds) ?entries[id]];
    final gone = visit.entryIds.length - seen.length;
    return _Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: Space.m),
        childrenPadding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(visit.clinicianName, style: text.labelLarge),
        subtitle: Text(
          '${formatShortDateTime(visit.accessedAt)} · ${_entries(visit.entryIds.length)}',
          style: text.labelMedium,
        ),
        children: [
          if (practice case final practice?) Text(practice, style: text.labelMedium),
          for (final entry in seen) _SeenEntry(entry),
          if (gone > 0) ...[
            const SizedBox(height: Space.s),
            Text('${_entries(gone)} no longer in your diary', style: text.labelMedium),
          ],
        ],
      ),
    );
  }
}

/// A compact entry the doctor saw: mood rail, mood name, day and time, symptoms.
class _SeenEntry extends StatelessWidget {
  const _SeenEntry(this.entry);

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: AppColors.paper, borderRadius: Radii.control),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: Space.xs, color: Mood.color(entry.mood)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(Mood.label(entry.mood), style: text.labelLarge),
                        const Spacer(),
                        Text(formatShortDateTime(entry.recordedAt), style: text.labelMedium),
                      ],
                    ),
                    if (entry.symptoms.isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Wrap(
                        spacing: Space.xs,
                        runSpacing: Space.xs,
                        children: [for (final s in entry.symptoms) SymptomTag(s)],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
