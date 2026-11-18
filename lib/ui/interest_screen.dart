import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/tax_rules.dart';
import '../data/providers.dart';
import '../logic/interest_report.dart';
import '../models/ais.dart';
import '../models/investment.dart';
import '../models/member.dart';
import 'ais_import_screen.dart';
import 'ais_section.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Interest earned per bank and the TDS each is likely to deduct.
class InterestScreen extends ConsumerStatefulWidget {
  const InterestScreen({super.key});

  @override
  ConsumerState<InterestScreen> createState() => _InterestScreenState();
}

class _InterestScreenState extends ConsumerState<InterestScreen> {
  TaxYear? _year;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final year = _year ?? TaxYear.of(today);
    final items = ref.watch(visibleInvestmentsProvider);
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final report = buildInterestReport(
      investments: items,
      members: members,
      year: year,
    );
    final membersById = {for (final m in members) m.id: m};
    final byMember = <String, List<PayerInterest>>{};
    for (final p in report.payers) {
      byMember.putIfAbsent(p.memberId, () => []).add(p);
    }
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final selected = ref.watch(selectedMemberProvider);
    final allInvestments =
        ref.watch(investmentsProvider).value ?? const <Investment>[];
    final statements =
        (ref.watch(aisStatementsProvider).value ?? const <AisStatement>[])
            .where(
              (s) =>
                  s.year == year &&
                  (selected == null || s.memberId == selected),
            )
            .toList();

    void openImport() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AisImportScreen(memberId: selected)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tax & TDS'),
        actions: [
          IconButton(
            tooltip: 'Import AIS',
            onPressed: openImport,
            icon: const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          const MemberFilterBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous year',
                      onPressed: () => setState(() => _year = year.previous),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        'Tax year ${year.label}',
                        textAlign: TextAlign.center,
                        style: t.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next year',
                      onPressed: () => setState(() => _year = year.next),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SectionCard(
                  child: StatGrid([
                    Stat('Taxable interest', formatInr(report.taxableInterest)),
                    Stat(
                      'Expected TDS',
                      formatInr(report.expectedTds),
                      valueColor: report.expectedTds > 0 ? c.warning : null,
                    ),
                    Stat(
                      'Tax-free interest (est.)',
                      formatInr(report.taxFreeTotal),
                    ),
                    Stat(
                      'Deposits earning',
                      '${report.payers.fold(0, (s, p) => s + p.items.length)}',
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Interest is counted in the year it is earned, even for cumulative FDs '
                    'that pay at maturity. That is how it is taxed too.',
                    style: t.bodySmall,
                  ),
                ),
                if (report.payers.isEmpty && report.taxFreeInterest.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No interest this year',
                    message: 'Add FDs, RDs or post office deposits with their rate to see interest and TDS here.',
                  ),
                for (final entry in byMember.entries) ...[
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      _memberHeading(membersById[entry.key], year),
                      style: t.labelSmall,
                    ),
                  ),
                  for (final p in entry.value) ...[
                    _PayerCard(payer: p),
                    const SizedBox(height: 10),
                  ],
                ],
                if (report.taxFreeInterest.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  SectionCard(
                    title: 'Tax-free interest (estimated)',
                    child: Column(
                      children: [
                        for (final (inv, amount) in report.taxFreeInterest)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(inv.name, style: t.bodyMedium),
                                ),
                                Text(formatInr(amount), style: t.titleSmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                for (final st in statements) ...[
                  const SizedBox(height: 18),
                  AisSection(
                    statement: st,
                    member: membersById[st.memberId],
                    investments: allInvestments,
                    today: today,
                  ),
                ],
                const SizedBox(height: 18),
                SectionCard(
                  title: statements.isEmpty
                      ? 'Check against AIS'
                      : 'Update AIS',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        statements.isEmpty
                            ? 'Import the AIS PDF from the income tax portal to see the TDS '
                                  'actually reported for ${year.label} and check it against your deposits.'
                            : 'AIS fills in every quarter. Import a fresh copy to update these numbers.',
                        style: t.bodyMedium?.copyWith(color: c.muted),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: openImport,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Import AIS PDF'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _memberHeading(Member? m, TaxYear year) {
    if (m == null) return 'UNKNOWN MEMBER';
    final senior = m.isSeniorIn(year) ? ' · SENIOR CITIZEN' : '';
    return '${m.name.toUpperCase()}$senior';
  }
}

class _PayerCard extends StatelessWidget {
  const _PayerCard({required this.payer});

  final PayerInterest payer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final fill = payer.threshold > 0
        ? (payer.interest / payer.threshold).clamp(0.0, 1.0)
        : 0.0;

    final (String status, Color color) = !payer.tdsApplicable
        ? ('No TDS on this', c.muted)
        : payer.form15Submitted
        ? ('Form 15G/15H submitted · no TDS expected', c.gain)
        : payer.crossesThreshold
        ? (
            'Over the ${formatInrCompact(payer.threshold)} limit · TDS ≈ ${formatInr(payer.expectedTds)}',
            c.warning,
          )
        : payer.nearThreshold
        ? (
            'Close to the ${formatInrCompact(payer.threshold)} limit · think about 15G/15H',
            c.warning,
          )
        : (
            'Under the ${formatInrCompact(payer.threshold)} limit · no TDS expected',
            c.gain,
          );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(payer.payer, style: t.titleMedium)),
              Text(formatInr(payer.interest), style: t.titleMedium),
            ],
          ),
          if (payer.tdsApplicable) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 6,
                backgroundColor: scheme.outlineVariant,
                color: payer.crossesThreshold && !payer.form15Submitted
                    ? c.warning
                    : scheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            status,
            style: t.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (payer.items.length > 1 ||
              payer.items.first.$1.name != payer.payer) ...[
            const SizedBox(height: 10),
            for (final (inv, amount) in payer.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${inv.name}${inv.ratePct == null ? '' : ' · ${inv.ratePct!.toStringAsFixed(2)}%'}',
                        style: t.bodySmall,
                      ),
                    ),
                    Text(formatInr(amount), style: t.bodySmall),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Exposed for the TDS limit text in tests.
String tdsLimitLabel(bool senior) => formatInrCompact(
  senior ? TaxRules.interestTdsThresholdSenior : TaxRules.interestTdsThreshold,
);
