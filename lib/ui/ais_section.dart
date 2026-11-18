import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/providers.dart';
import '../logic/ais_match.dart';
import '../models/ais.dart';
import '../models/investment.dart';
import '../models/member.dart';
import '../theme/app_theme.dart';
import 'ais_import_screen.dart';
import 'widgets/common.dart';

/// What one member's imported AIS says for the year, and how it compares
/// with the deposits in the app.
class AisSection extends ConsumerWidget {
  const AisSection({
    super.key,
    required this.statement,
    required this.member,
    required this.investments,
    required this.today,
  });

  final AisStatement statement;
  final Member? member;
  final List<Investment> investments;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final s = statement;
    final tds = s.tdsRecords.toList();
    final salaryTds = tds
        .where((r) => r.isSalary)
        .fold(0.0, (a, r) => a + r.tdsDeducted);
    final interestTds = tds
        .where((r) => r.isInterest)
        .fold(0.0, (a, r) => a + r.tdsDeducted);
    final otherTds = s.totalTds - salaryTds - interestTds;
    final paid = s.payments.fold(0.0, (a, p) => a + p.amount);
    final comparisons = compareInterest(
      statement: s,
      investments: investments,
      today: today,
    );
    final others = s.records.where((r) => !r.isTds && !r.isTcs).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'AIS · ${(member?.name ?? 'Unknown').toUpperCase()}',
                  style: t.labelSmall,
                ),
              ),
              if (s.importedAt != null)
                Text(
                  'Imported ${formatDate(s.importedAt!)}',
                  style: t.bodySmall,
                ),
              PopupMenuButton<String>(
                tooltip: 'AIS options',
                onSelected: (v) async {
                  if (v == 'remove') {
                    await ref
                        .read(repositoryProvider)
                        ?.deleteAisStatement(s.docId);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove this AIS'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          child: StatGrid([
            Stat('TDS / TCS in AIS', formatInr(s.totalTds)),
            if (salaryTds > 0) Stat('On salary', formatInr(salaryTds)),
            if (interestTds > 0) Stat('On interest', formatInr(interestTds)),
            if (otherTds > 0.5) Stat('Other TDS / TCS', formatInr(otherTds)),
            if (paid > 0) Stat('Tax paid (advance / self)', formatInr(paid)),
            for (final r in s.refunds)
              Stat(
                'Refund for ${r.forYear}',
                '${formatInr(r.amount)}${r.date == null ? '' : ' · ${formatDayMonth(r.date!)}'}',
              ),
          ]),
        ),
        if (comparisons.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            title: 'Interest: app vs AIS',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, cmp) in comparisons.indexed) ...[
                  if (i > 0) const Divider(height: 24),
                  _ComparisonRow(cmp: cmp),
                ],
                const SizedBox(height: 12),
                Text(
                  'Banks report every quarter, so AIS lags a few months. The app\'s '
                  'figure is counted up to the same date as AIS.',
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
        ],
        if (tds.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            title: 'TDS / TCS by source',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, r) in tds.indexed) ...[
                  if (i > 0) const Divider(height: 24),
                  AisRecordTile(record: r),
                ],
              ],
            ),
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            title: 'Other information in AIS',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, r) in others.indexed) ...[
                  if (i > 0) const Divider(height: 24),
                  AisRecordTile(record: r),
                ],
              ],
            ),
          ),
        ],
        if (tds.isEmpty && others.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'This AIS has no entries yet.',
              style: t.bodyMedium?.copyWith(color: c.muted),
            ),
          ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.cmp});

  final InterestComparison cmp;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final upTo = cmp.upTo == null ? '' : ' (to ${formatDayMonth(cmp.upTo!)})';
    final (String note, Color color) = switch (cmp.check) {
      InterestCheck.matches => ('Matches AIS', c.gain),
      InterestCheck.aisHigher => (
        'AIS shows ${formatInr(cmp.difference)} more: a deposit may be missing in the app',
        c.warning,
      ),
      InterestCheck.aisLower => (
        'AIS shows ${formatInr(-cmp.difference)} less: check the rate, or the bank hasn\'t reported yet',
        c.warning,
      ),
      InterestCheck.notInAis => ('Not in AIS yet', c.muted),
      InterestCheck.notInApp => (
        'In AIS but not in the app: add this deposit?',
        c.warning,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          cmp.payer,
          style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (cmp.check != InterestCheck.notInApp)
              Expanded(
                child: Stat('App estimate$upTo', formatInr(cmp.appInterest)),
              ),
            if (cmp.check != InterestCheck.notInAis)
              Expanded(child: Stat('AIS interest', formatInr(cmp.aisInterest))),
            if (cmp.check != InterestCheck.notInAis)
              Expanded(child: Stat('AIS TDS', formatInr(cmp.aisTds))),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          note,
          style: t.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
