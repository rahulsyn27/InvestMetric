import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/providers.dart';
import '../logic/upcoming_events.dart';
import '../theme/app_theme.dart';
import 'investment_detail_screen.dart';
import 'widgets/common.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  bool _taxDates = true;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final items = ref.watch(visibleInvestmentsProvider);
    final events = upcomingEvents(
      items,
      today,
      days: 365,
      includeTaxDates: _taxDates,
    );
    final t = Theme.of(context).textTheme;

    final byMonth = <String, List<UpcomingEvent>>{};
    final overdue = <UpcomingEvent>[];
    for (final e in events) {
      if (e.kind == EventKind.overdueMaturity) {
        overdue.add(e);
        continue;
      }
      byMonth
          .putIfAbsent(DateFormat('MMMM yyyy').format(e.date), () => [])
          .add(e);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: Column(
        children: [
          const MemberFilterBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _taxDates,
              onChanged: (v) => setState(() => _taxDates = v),
              title: const Text('Show tax deadlines'),
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? const EmptyState(
                    icon: Icons.event_available_outlined,
                    title: 'Nothing coming up',
                    message: 'Maturity dates, RD instalments, SIPs and interest payouts show up here.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      if (overdue.isNotEmpty) ...[
                        SectionCard(
                          title: 'Needs your attention',
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Column(
                            children: [
                              for (final e in overdue)
                                EventTile(event: e, today: today),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      for (final entry in byMonth.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                          child: Text(
                            entry.key.toUpperCase(),
                            style: t.labelSmall,
                          ),
                        ),
                        SectionCard(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            children: [
                              for (final e in entry.value)
                                EventTile(event: e, today: today),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One dated row: date block, title, amount.
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, required this.today});

  final UpcomingEvent event;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final urgent =
        event.kind == EventKind.overdueMaturity ||
        (event.needsAction && daysBetween(today, event.date) <= 15);
    final accent = urgent
        ? c.warning
        : event.kind == EventKind.tax
        ? scheme.secondary
        : scheme.primary;
    final inv = event.investment;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: inv == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => InvestmentDetailScreen(investmentId: inv.id),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${event.date.day}',
                    style: t.titleMedium?.copyWith(color: accent, height: 1.1),
                  ),
                  Text(
                    DateFormat('MMM').format(event.date).toUpperCase(),
                    style: t.labelSmall?.copyWith(color: accent, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (event.subtitle.isNotEmpty)
                    Text(
                      event.subtitle,
                      style: t.bodySmall?.copyWith(
                        color: urgent ? c.warning : null,
                      ),
                    ),
                ],
              ),
            ),
            if (event.amount != null && event.kind != EventKind.payout) ...[
              const SizedBox(width: 8),
              Text(formatInr(event.amount!), style: t.titleSmall),
            ],
          ],
        ),
      ),
    );
  }
}
