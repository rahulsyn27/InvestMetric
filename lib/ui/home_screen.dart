import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/providers.dart';
import '../logic/interest_report.dart';
import '../logic/upcoming_events.dart';
import '../logic/valuation.dart';
import '../models/investment.dart';
import '../theme/app_theme.dart';
import 'calendar_screen.dart';
import 'home_shell.dart';
import 'investment_form_screen.dart';
import 'widgets/common.dart';
import 'widgets/returns_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final loading = ref.watch(investmentsProvider).isLoading;
    final items = ref.watch(visibleInvestmentsProvider);
    final members = ref.watch(membersProvider).value ?? const [];
    final active = items.where((i) => !i.isClosed).toList();
    final total = totalValuation(active, today);
    final slices = byAssetType(active, today);
    final events = upcomingEvents(
      items,
      today,
      days: 60,
      includeTaxDates: true,
    ).take(4).toList();
    final year = TaxYear.of(today);
    final report = buildInterestReport(
      investments: items,
      members: members,
      year: year,
    );
    final t = Theme.of(context).textTheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'home-add',
        onPressed: () => startAddInvestment(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatDate(today), style: t.bodySmall),
                  const SizedBox(height: 2),
                  Text('Portfolio', style: t.headlineMedium),
                ],
              ),
            ),
            const MemberFilterBar(),
            const SizedBox(height: 8),
            if (loading && items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (active.isEmpty)
              EmptyState(
                icon: Icons.savings_outlined,
                title: 'Add your first investment',
                message:
                    'Start with an FD or a mutual fund. You can add investments '
                    'for family members too, from the Family tab.',
                action: FilledButton.icon(
                  onPressed: () => startAddInvestment(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add investment'),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _HeroCard(total: total, count: active.length),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ReturnsCard(items: active),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SectionCard(
                  title: 'Where your money is',
                  trailing: TextButton(
                    onPressed: () => onOpenTab(Tabs.holdings),
                    child: const Text('Details'),
                  ),
                  child: _Allocation(slices: slices, total: total.current),
                ),
              ),
            ],
            if (events.isNotEmpty) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SectionCard(
                  title: 'Coming up',
                  trailing: TextButton(
                    onPressed: () => onOpenTab(Tabs.calendar),
                    child: const Text('Calendar'),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      for (final e in events) EventTile(event: e, today: today),
                    ],
                  ),
                ),
              ),
            ],
            if (report.payers.isNotEmpty ||
                report.taxFreeInterest.isNotEmpty) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SectionCard(
                  title: 'Interest · tax year ${year.label}',
                  trailing: TextButton(
                    onPressed: () => onOpenTab(Tabs.interest),
                    child: const Text('Details'),
                  ),
                  child: StatGrid([
                    Stat('Taxable interest', formatInr(report.taxableInterest)),
                    Stat(
                      'Expected TDS',
                      formatInr(report.expectedTds),
                      valueColor: report.expectedTds > 0
                          ? context.colors.warning
                          : null,
                    ),
                    if (report.taxFreeTotal > 0)
                      Stat(
                        'Tax-free (PPF/EPF, est.)',
                        formatInr(report.taxFreeTotal),
                      ),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.total, required this.count});

  final Valuation total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.hero,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current value',
            style: t.bodySmall?.copyWith(color: c.heroMuted),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatInr(total.current),
              style: t.displaySmall?.copyWith(color: c.heroText),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'Invested',
                  value: formatInrCompact(total.invested),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total gain',
                      style: t.bodySmall?.copyWith(color: c.heroMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatInrCompact(total.gain),
                      style: t.titleSmall?.copyWith(
                        color: total.gain >= 0 ? c.gain : c.loss,
                      ),
                    ),
                    if (total.gainPct != null)
                      Text(
                        formatPct(total.gainPct!, showSign: true),
                        style: t.bodySmall?.copyWith(
                          color: total.gain >= 0 ? c.gain : c.loss,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _HeroStat(label: 'Holdings', value: '$count'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.bodySmall?.copyWith(color: c.heroMuted)),
        const SizedBox(height: 2),
        Text(value, style: t.titleSmall?.copyWith(color: c.heroText)),
      ],
    );
  }
}

class _Allocation extends StatelessWidget {
  const _Allocation({required this.slices, required this.total});

  final List<(AssetType, Valuation)> slices;
  final double total;

  @override
  Widget build(BuildContext context) {
    final typed = slices;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AllocationBar(typed),
        const SizedBox(height: 14),
        for (final s in typed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: s.$1.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.$1.label, style: t.bodyMedium)),
                Text(formatInrCompact(s.$2.current), style: t.bodyMedium),
                SizedBox(
                  width: 64,
                  child: Text(
                    total > 0 ? formatPct(s.$2.current / total * 100) : '–',
                    textAlign: TextAlign.right,
                    style: t.titleSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
