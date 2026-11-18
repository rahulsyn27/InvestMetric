import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/providers.dart';
import '../../logic/nav_history.dart';
import '../../logic/returns.dart';
import '../../models/investment.dart';
import '../../models/snapshot.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// Gain over 1M · 3M · 6M · 1Y · this tax year · all time, split into
/// interest earned and market change. Used on Home (all visible holdings)
/// and on a holding's detail screen.
class ReturnsCard extends ConsumerWidget {
  const ReturnsCard({super.key, required this.items, this.single = false});

  final List<Investment> items;

  /// Detail screen: only show the parts that apply to this holding.
  final bool single;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final period = ref.watch(returnPeriodProvider);
    final from = period.startFor(today);

    final codes = from == null ? const <String>{} : navCodesNeeded(items, from);
    final req = from == null ? null : navRequest(from, codes);
    final AsyncValue<Map<String, DatedNav>> navs = codes.isEmpty
        ? const AsyncData({})
        : ref.watch(navsOnProvider(req!));
    final AsyncValue<ValueSnapshot?> snap = from == null
        ? const AsyncData(null)
        : ref.watch(snapshotOnOrBeforeProvider(from));
    final loading = navs.isLoading || snap.isLoading;

    final r = periodReturn(
      items,
      period,
      today,
      ReturnInputs(navs: navs.value ?? const {}, snapshot: snap.value),
    );

    final t = Theme.of(context).textTheme;
    final c = context.colors;

    Widget body;
    if (loading) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                codes.isEmpty
                    ? 'Working out returns…'
                    : 'Getting past NAVs from AMFI…',
                style: t.bodyMedium?.copyWith(color: c.muted),
              ),
            ),
          ],
        ),
      );
    } else if (r.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          single
              ? 'No value saved for ${formatDate(from!)} yet. Returns for this '
                    'holding build up from the day it is first saved.'
              : 'Nothing to show for this period yet.',
          style: t.bodyMedium?.copyWith(color: c.muted),
        ),
      );
    } else {
      body = _Result(r: r, single: single, item: single ? items.first : null);
    }

    final notes = <Widget>[
      if (!loading && navs.hasError)
        Row(
          children: [
            Expanded(
              child: Text(
                'Couldn\'t get past NAVs from AMFI.',
                style: t.bodySmall?.copyWith(color: c.warning),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(navsOnProvider(req!)),
              child: const Text('Retry'),
            ),
          ],
        ),
      if (!loading && !single && r.leftOut.isNotEmpty && from != null)
        Text(
          'Not counted: ${_names(r.leftOut)}. No value was saved on or before '
          '${formatDate(from)}. Stocks and balances build up a history from '
          'the day the app first saves them.',
          style: t.bodySmall,
        ),
    ];

    return SectionCard(
      title: 'Returns',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PeriodChips(),
          const SizedBox(height: 14),
          body,
          for (final n in notes) ...[const SizedBox(height: 10), n],
        ],
      ),
    );
  }

  String _names(List<Investment> list) {
    final names = list.map((i) => i.name).toList();
    if (names.length <= 2) return names.join(' and ');
    return '${names.take(2).join(', ')} and ${names.length - 2} more';
  }
}

class _PeriodChips extends ConsumerWidget {
  const _PeriodChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(returnPeriodProvider);
    final notifier = ref.read(returnPeriodProvider.notifier);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final p in ReturnPeriod.values)
          ChoiceChip(
            label: Text(p.label),
            selected: p == selected,
            onSelected: (_) => notifier.select(p),
          ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.r, required this.single, this.item});

  final PeriodReturn r;
  final bool single;
  final Investment? item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final gain = r.gain;
    final color = gain > 0.5 ? c.gain : (gain < -0.5 ? c.loss : c.muted);
    final pct = r.gainPct;
    final from = r.from;

    final kind = item?.type.kind;
    final showInterest =
        !single ||
        kind == ValuationKind.deposit ||
        (item?.type.interestTaxFree ?? false);
    final showMarket = !single || !showInterest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          from == null
              ? 'Gain since you started'
              : 'Gain since ${formatDate(from)}',
          style: t.bodySmall,
        ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 10,
          children: [
            Text(
              formatInr(gain, showSign: true),
              style: t.headlineSmall?.copyWith(color: color),
            ),
            if (pct != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  formatPct(pct, showSign: true),
                  style: t.titleSmall?.copyWith(color: color),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        StatGrid([
          if (showInterest) Stat('Interest earned', formatInr(r.interest)),
          if (showMarket)
            Stat(
              item?.type.kind == ValuationKind.balance
                  ? 'Change in balance'
                  : 'Market change',
              formatInr(r.marketChange, showSign: true),
              valueColor: r.marketChange > 0.5
                  ? c.gain
                  : (r.marketChange < -0.5 ? c.loss : null),
            ),
          if (from != null)
            Stat('Value on ${formatDayMonth(from)}', formatInr(r.startValue)),
          Stat(
            from == null ? 'Money put in' : 'Money added',
            formatInr(r.added),
          ),
          if (r.paidOut.abs() >= 1)
            Stat('Interest paid out', formatInr(r.paidOut)),
          Stat('Value now', formatInr(r.endValue)),
        ]),
        const SizedBox(height: 12),
        Text(
          from == null
              ? '% is of the money put in. Includes interest already paid out.'
              : '% is for the period (not yearly) and allows for money '
                    'added during it.',
          style: t.bodySmall,
        ),
      ],
    );
  }
}
